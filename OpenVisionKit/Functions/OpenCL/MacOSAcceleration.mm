//     *************************** LiveVisionKit ****************************
//     Copyright (C) 2022  Sebastian Di Marco (crowsinc.dev@gmail.com)
//
//     This program is free software: you can redistribute it and/or modify
//     it under the terms of the GNU General Public License as published by
//     the Free Software Foundation, either version 3 of the License, or
//     (at your option) any later version.
//
//     This program is distributed in the hope that it will be useful,
//     but WITHOUT ANY WARRANTY; without even the implied warranty of
//     MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
//     GNU General Public License for more details.
//
//     You should have received a copy of the GNU General Public License
//     along with this program.  If not, see <https://www.gnu.org/licenses/>.
//     **********************************************************************

#ifdef MACOS_BUILD

#include "MacOSAcceleration.hpp"
#include "../../Directives.hpp"

#ifdef MACOS_OPENCL_AVAILABLE
#include <OpenCL/OpenCL.h>
#endif

#ifdef MACOS_METAL_AVAILABLE
#include <Metal/Metal.h>
#endif

#ifdef MACOS_MPS_AVAILABLE
#include <MetalPerformanceShaders/MetalPerformanceShaders.h>
#endif

#include <Accelerate/Accelerate.h>
#include <dispatch/dispatch.h>
#include <sys/sysctl.h>
#include <chrono>

namespace lvk::ocl::macos
{

//---------------------------------------------------------------------------------------------------------------------
// GPU Capabilities Detection
//---------------------------------------------------------------------------------------------------------------------

bool initialize_gpu_acceleration()
{
    bool success = true;
    
    // Initialize OpenCL context
    auto& opencl_context = MacOSOpenCLContext::instance();
    if (!opencl_context.initialize())
    {
        success = false;
    }
    
#ifdef MACOS_MPS_AVAILABLE
    // Initialize Metal acceleration
    auto& metal_accel = MetalAcceleration::instance();
    if (!metal_accel.initialize())
    {
        // Metal failure is not critical, continue
    }
#endif
    
    // Initialize Accelerate framework
    auto& accelerate = AccelerateIntegration::instance();
    if (!accelerate.initialize())
    {
        // Accelerate failure is not critical, continue
    }
    
    // Initialize GCD parallelism
    auto& gcd = GCDParallelism::instance();
    if (!gcd.initialize())
    {
        // GCD failure is not critical, continue
    }
    
    // Initialize GPU acceleration manager
    auto& manager = GPUAccelerationManager::instance();
    if (!manager.initialize())
    {
        success = false;
    }
    
    return success;
}

GPUCapabilities get_gpu_capabilities()
{
    return GPUAccelerationManager::instance().capabilities();
}

//---------------------------------------------------------------------------------------------------------------------
// MacOSOpenCLContext Implementation
//---------------------------------------------------------------------------------------------------------------------

MacOSOpenCLContext& MacOSOpenCLContext::instance()
{
    static MacOSOpenCLContext instance;
    return instance;
}

MacOSOpenCLContext::~MacOSOpenCLContext()
{
    release();
}

bool MacOSOpenCLContext::initialize()
{
    if (m_initialized)
        return m_available;
    
    m_initialized = true;
    
    if (!detect_opencl_support())
    {
        m_available = false;
        return false;
    }
    
    if (!setup_opencl_context())
    {
        m_available = false;
        return false;
    }
    
    m_available = true;
    return true;
}

void MacOSOpenCLContext::release()
{
    if (m_initialized && m_available)
    {
        // OpenCV handles OpenCL context cleanup automatically
        m_available = false;
    }
    m_initialized = false;
}

bool MacOSOpenCLContext::detect_opencl_support()
{
#ifdef MACOS_OPENCL_AVAILABLE
    // Check if OpenCV has OpenCL support
    if (!cv::ocl::haveOpenCL())
    {
        return false;
    }
    
    // Check if there are any OpenCL devices available
    std::vector<cv::ocl::PlatformInfo> platforms;
    cv::ocl::getPlatfomsInfo(platforms);
    
    if (platforms.empty())
    {
        return false;
    }
    
    // Look for a suitable device
    for (const auto& platform : platforms)
    {
        int numDevices = platform.deviceNumber();
        for (int i = 0; i < numDevices; ++i)
        {
            cv::ocl::Device device;
            platform.getDevice(device, i);
            if (device.type() == cv::ocl::Device::TYPE_GPU || 
                device.type() == cv::ocl::Device::TYPE_ACCELERATOR)
            {
                return true;
            }
        }
    }
    
    return false;
#else
    return false;
#endif
}

bool MacOSOpenCLContext::setup_opencl_context()
{
#ifdef MACOS_OPENCL_AVAILABLE
    try
    {
        // Use OpenCV's default OpenCL context setup
        cv::ocl::setUseOpenCL(true);
        
        if (!cv::ocl::haveOpenCL())
        {
            return false;
        }
        
        m_context = cv::ocl::Context::getDefault();
        m_device = cv::ocl::Device::getDefault();
        
        if (m_context.empty() || m_device.empty())
        {
            return false;
        }
        
        return true;
    }
    catch (const cv::Exception& e)
    {
        return false;
    }
#else
    return false;
#endif
}

bool MacOSOpenCLContext::try_gpu_operation(std::function<bool()> gpu_operation, 
                                          std::function<bool()> cpu_fallback)
{
    if (!m_available)
    {
        return cpu_fallback();
    }
    
    try
    {
        // Try GPU operation first
        if (gpu_operation())
        {
            return true;
        }
    }
    catch (const cv::Exception& e)
    {
        // GPU operation failed, fall back to CPU
    }
    
    // Fall back to CPU implementation
    return cpu_fallback();
}

std::string MacOSOpenCLContext::get_device_name() const
{
    if (!m_available || m_device.empty())
        return "No OpenCL device";
    
    return m_device.name();
}

size_t MacOSOpenCLContext::get_device_memory() const
{
    if (!m_available || m_device.empty())
        return 0;
    
    return m_device.globalMemSize() / (1024 * 1024); // Convert to MB
}

#ifdef MACOS_MPS_AVAILABLE
//---------------------------------------------------------------------------------------------------------------------
// MetalAcceleration Implementation
//---------------------------------------------------------------------------------------------------------------------

MetalAcceleration& MetalAcceleration::instance()
{
    static MetalAcceleration instance;
    return instance;
}

MetalAcceleration::~MetalAcceleration()
{
    release();
}

bool MetalAcceleration::initialize()
{
    if (m_available)
        return true;
    
    return setup_metal_device();
}

void MetalAcceleration::release()
{
    if (m_command_queue)
    {
        [m_command_queue release];
        m_command_queue = nil;
    }
    
    if (m_device)
    {
        [m_device release];
        m_device = nil;
    }
    
    m_available = false;
}

bool MetalAcceleration::setup_metal_device()
{
    @autoreleasepool {
        m_device = MTLCreateSystemDefaultDevice();
        if (!m_device)
        {
            return false;
        }
        
        m_command_queue = [m_device newCommandQueue];
        if (!m_command_queue)
        {
            [m_device release];
            m_device = nil;
            return false;
        }
        
        m_available = true;
        return true;
    }
}

bool MetalAcceleration::gaussian_blur(const cv::UMat& src, cv::UMat& dst, 
                                     cv::Size kernel_size, double sigma)
{
    if (!m_available)
        return false;
    
    // This is a placeholder for MPS Gaussian blur implementation
    // In a full implementation, you would:
    // 1. Convert cv::UMat to Metal texture
    // 2. Create MPSImageGaussianBlur kernel
    // 3. Execute the kernel
    // 4. Convert result back to cv::UMat
    
    // For now, fall back to OpenCV implementation
    return false;
}

bool MetalAcceleration::convolution(const cv::UMat& src, cv::UMat& dst, const cv::Mat& kernel)
{
    if (!m_available)
        return false;
    
    // Placeholder for MPS convolution implementation
    return false;
}

bool MetalAcceleration::histogram_equalization(const cv::UMat& src, cv::UMat& dst)
{
    if (!m_available)
        return false;
    
    // Placeholder for MPS histogram equalization implementation
    return false;
}
#endif

//---------------------------------------------------------------------------------------------------------------------
// AccelerateIntegration Implementation
//---------------------------------------------------------------------------------------------------------------------

AccelerateIntegration& AccelerateIntegration::instance()
{
    static AccelerateIntegration instance;
    return instance;
}

bool AccelerateIntegration::initialize()
{
    // Accelerate framework is always available on macOS
    m_available = true;
    return true;
}

void AccelerateIntegration::release()
{
    // Nothing to release for Accelerate framework
}

void AccelerateIntegration::matrix_multiply(const float* a, const float* b, float* c, 
                                          size_t m, size_t n, size_t k)
{
    if (!m_available)
        return;
    
    // Use BLAS from Accelerate framework for optimized matrix multiplication
    cblas_sgemm(CblasRowMajor, CblasNoTrans, CblasNoTrans,
                static_cast<int>(m), static_cast<int>(n), static_cast<int>(k),
                1.0f, a, static_cast<int>(k), b, static_cast<int>(n),
                0.0f, c, static_cast<int>(n));
}

void AccelerateIntegration::vector_add(const float* a, const float* b, float* result, size_t count)
{
    if (!m_available)
        return;
    
    // Use vDSP for optimized vector operations
    vDSP_vadd(a, 1, b, 1, result, 1, count);
}

void AccelerateIntegration::vector_multiply(const float* a, const float* b, float* result, size_t count)
{
    if (!m_available)
        return;
    
    vDSP_vmul(a, 1, b, 1, result, 1, count);
}

void AccelerateIntegration::fft_forward(const float* input, float* output, size_t length)
{
    if (!m_available)
        return;
    
    // Use vDSP for optimized FFT operations
    vDSP_Length log2n = static_cast<vDSP_Length>(log2(length));
    FFTSetup fft_setup = vDSP_create_fftsetup(log2n, FFT_RADIX2);
    
    if (fft_setup)
    {
        DSPSplitComplex split_complex;
        split_complex.realp = output;
        split_complex.imagp = output + length / 2;
        
        // Copy input to output (assuming real input)
        memcpy(output, input, length * sizeof(float));
        
        vDSP_ctoz((DSPComplex*)output, 2, &split_complex, 1, length / 2);
        vDSP_fft_zrip(fft_setup, &split_complex, 1, log2n, FFT_FORWARD);
        
        vDSP_destroy_fftsetup(fft_setup);
    }
}

void AccelerateIntegration::fft_inverse(const float* input, float* output, size_t length)
{
    if (!m_available)
        return;
    
    vDSP_Length log2n = static_cast<vDSP_Length>(log2(length));
    FFTSetup fft_setup = vDSP_create_fftsetup(log2n, FFT_RADIX2);
    
    if (fft_setup)
    {
        DSPSplitComplex split_complex;
        split_complex.realp = const_cast<float*>(input);
        split_complex.imagp = const_cast<float*>(input) + length / 2;
        
        vDSP_fft_zrip(fft_setup, &split_complex, 1, log2n, FFT_INVERSE);
        vDSP_ztoc(&split_complex, 1, (DSPComplex*)output, 2, length / 2);
        
        // Scale the result
        float scale = 1.0f / length;
        vDSP_vsmul(output, 1, &scale, output, 1, length);
        
        vDSP_destroy_fftsetup(fft_setup);
    }
}

//---------------------------------------------------------------------------------------------------------------------
// GCDParallelism Implementation
//---------------------------------------------------------------------------------------------------------------------

GCDParallelism& GCDParallelism::instance()
{
    static GCDParallelism instance;
    return instance;
}

bool GCDParallelism::initialize()
{
    if (m_available)
        return true;
    
    // Get the number of CPU cores
    size_t size = sizeof(m_thread_count);
    if (sysctlbyname("hw.ncpu", &m_thread_count, &size, nullptr, 0) != 0)
    {
        m_thread_count = 1; // Fallback to single thread
    }
    
    m_available = true;
    return true;
}

void GCDParallelism::release()
{
    // Nothing to release for GCD
}

size_t GCDParallelism::get_optimal_thread_count() const
{
    return m_thread_count;
}

//---------------------------------------------------------------------------------------------------------------------
// GPUAccelerationManager Implementation
//---------------------------------------------------------------------------------------------------------------------

GPUAccelerationManager& GPUAccelerationManager::instance()
{
    static GPUAccelerationManager instance;
    return instance;
}

bool GPUAccelerationManager::initialize()
{
    if (m_initialized)
        return true;
    
    // Detect GPU capabilities
    m_capabilities.opencl_available = MacOSOpenCLContext::instance().is_available();
    
#ifdef MACOS_MPS_AVAILABLE
    m_capabilities.mps_available = MetalAcceleration::instance().is_available();
#endif
    
    m_capabilities.metal_available = m_capabilities.mps_available;
    
    // Get GPU information from OpenCL if available
    if (m_capabilities.opencl_available)
    {
        auto& opencl = MacOSOpenCLContext::instance();
        m_capabilities.gpu_name = opencl.get_device_name();
        m_capabilities.gpu_memory_mb = opencl.get_device_memory();
        
        // Determine if GPU is integrated or discrete based on memory size
        // This is a heuristic - integrated GPUs typically have less dedicated memory
        m_capabilities.integrated_gpu = (m_capabilities.gpu_memory_mb < 1024);
        m_capabilities.discrete_gpu = !m_capabilities.integrated_gpu;
    }
    
    m_initialized = true;
    return true;
}

void GPUAccelerationManager::release()
{
    MacOSOpenCLContext::instance().release();
    
#ifdef MACOS_MPS_AVAILABLE
    MetalAcceleration::instance().release();
#endif
    
    AccelerateIntegration::instance().release();
    GCDParallelism::instance().release();
    
    m_initialized = false;
}

GPUAccelerationManager::AccelerationType 
GPUAccelerationManager::get_best_acceleration(const std::string& operation_type) const
{
    // Prioritize acceleration methods based on operation type and availability
    
    if (operation_type == "matrix_multiply" || operation_type == "fft")
    {
        // Accelerate framework is best for math operations
        return AccelerationType::ACCELERATE;
    }
    
    if (operation_type == "image_processing" || operation_type == "convolution")
    {
        // Prefer OpenCL for image processing
        if (m_capabilities.opencl_available)
            return AccelerationType::OPENCL;
        
#ifdef MACOS_MPS_AVAILABLE
        if (m_capabilities.mps_available)
            return AccelerationType::METAL_MPS;
#endif
    }
    
    if (operation_type == "parallel_loop")
    {
        // Use GCD for parallel loops
        return AccelerationType::GCD_PARALLEL;
    }
    
    // Default fallback order
    if (m_capabilities.opencl_available)
        return AccelerationType::OPENCL;
    
#ifdef MACOS_MPS_AVAILABLE
    if (m_capabilities.mps_available)
        return AccelerationType::METAL_MPS;
#endif
    
    return AccelerationType::CPU_FALLBACK;
}

void GPUAccelerationManager::start_performance_monitoring()
{
    m_monitoring_enabled = true;
}

void GPUAccelerationManager::stop_performance_monitoring()
{
    m_monitoring_enabled = false;
}

double GPUAccelerationManager::get_average_execution_time(const std::string& operation_type) const
{
    auto it = m_execution_times.find(operation_type);
    if (it == m_execution_times.end() || it->second.empty())
        return 0.0;
    
    double sum = 0.0;
    for (double time : it->second)
        sum += time;
    
    return sum / it->second.size();
}

} // namespace lvk::ocl::macos

#endif // MACOS_BUILD