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

#pragma once

#ifdef MACOS_BUILD

#include <opencv2/opencv.hpp>
#include <opencv2/core/ocl.hpp>

#ifdef MACOS_OPENCL_AVAILABLE
#include <OpenCL/OpenCL.h>
#endif

#ifdef MACOS_METAL_AVAILABLE
// Forward declarations to avoid including Objective-C headers in C++ header
#ifdef __OBJC__
#include <Metal/Metal.h>
#else
// Forward declarations for C++ compilation
typedef struct objc_object* id;
#endif
#endif

#ifdef MACOS_MPS_AVAILABLE
#ifdef __OBJC__
#include <MetalPerformanceShaders/MetalPerformanceShaders.h>
#endif
#endif

namespace lvk::ocl::macos
{
    // GPU acceleration capability detection
    struct GPUCapabilities
    {
        bool opencl_available = false;
        bool metal_available = false;
        bool mps_available = false;
        bool integrated_gpu = false;
        bool discrete_gpu = false;
        std::string gpu_name;
        size_t gpu_memory_mb = 0;
    };

    // Initialize macOS GPU acceleration systems
    bool initialize_gpu_acceleration();
    
    // Get current GPU capabilities
    GPUCapabilities get_gpu_capabilities();
    
    // OpenCL context management for macOS
    class MacOSOpenCLContext
    {
    public:
        static MacOSOpenCLContext& instance();
        
        bool initialize();
        void release();
        
        bool is_available() const { return m_available; }
        bool is_initialized() const { return m_initialized; }
        
        // Fallback mechanism - try OpenCL first, then CPU
        bool try_gpu_operation(std::function<bool()> gpu_operation, 
                              std::function<bool()> cpu_fallback);
        
        // Get OpenCL device information
        std::string get_device_name() const;
        size_t get_device_memory() const;
        
    private:
        MacOSOpenCLContext() = default;
        ~MacOSOpenCLContext();
        
        bool m_available = false;
        bool m_initialized = false;
        cv::ocl::Context m_context;
        cv::ocl::Device m_device;
        
        bool detect_opencl_support();
        bool setup_opencl_context();
    };

#ifdef MACOS_MPS_AVAILABLE
    // Metal Performance Shaders integration for specific operations
    class MetalAcceleration
    {
    public:
        static MetalAcceleration& instance();
        
        bool initialize();
        void release();
        
        bool is_available() const { return m_available; }
        
        // MPS-accelerated operations where beneficial
        bool gaussian_blur(const cv::UMat& src, cv::UMat& dst, cv::Size kernel_size, double sigma);
        bool convolution(const cv::UMat& src, cv::UMat& dst, const cv::Mat& kernel);
        bool histogram_equalization(const cv::UMat& src, cv::UMat& dst);
        
    private:
        MetalAcceleration() = default;
        ~MetalAcceleration();
        
        bool m_available = false;
        id<MTLDevice> m_device = nil;
        id<MTLCommandQueue> m_command_queue = nil;
        
        bool setup_metal_device();
    };
#endif

    // Accelerate framework integration for math operations
    class AccelerateIntegration
    {
    public:
        static AccelerateIntegration& instance();
        
        bool initialize();
        void release();
        
        bool is_available() const { return m_available; }
        
        // Accelerate-optimized math operations
        void matrix_multiply(const float* a, const float* b, float* c, 
                           size_t m, size_t n, size_t k);
        void vector_add(const float* a, const float* b, float* result, size_t count);
        void vector_multiply(const float* a, const float* b, float* result, size_t count);
        void fft_forward(const float* input, float* output, size_t length);
        void fft_inverse(const float* input, float* output, size_t length);
        
    private:
        AccelerateIntegration() = default;
        
        bool m_available = false;
    };

    // Grand Central Dispatch parallel processing utilities
    class GCDParallelism
    {
    public:
        static GCDParallelism& instance();
        
        bool initialize();
        void release();
        
        bool is_available() const { return m_available; }
        
        // Parallel processing using GCD
        template<typename Func>
        void parallel_for(size_t start, size_t end, Func&& func);
        
        template<typename Func>
        void parallel_for_2d(size_t width, size_t height, Func&& func);
        
        // Get optimal thread count for current system
        size_t get_optimal_thread_count() const;
        
    private:
        GCDParallelism() = default;
        
        bool m_available = false;
        size_t m_thread_count = 0;
    };

    // Unified GPU acceleration manager
    class GPUAccelerationManager
    {
    public:
        static GPUAccelerationManager& instance();
        
        bool initialize();
        void release();
        
        // Get the best available acceleration method for an operation
        enum class AccelerationType
        {
            OPENCL,
            METAL_MPS,
            ACCELERATE,
            GCD_PARALLEL,
            CPU_FALLBACK
        };
        
        AccelerationType get_best_acceleration(const std::string& operation_type) const;
        
        // Execute operation with best available acceleration
        template<typename Func>
        bool execute_accelerated(const std::string& operation_type, Func&& operation);
        
        // Performance monitoring
        void start_performance_monitoring();
        void stop_performance_monitoring();
        double get_average_execution_time(const std::string& operation_type) const;
        
        // Get GPU capabilities
        const GPUCapabilities& capabilities() const { return m_capabilities; }
        
    private:
        GPUAccelerationManager() = default;
        
        bool m_initialized = false;
        GPUCapabilities m_capabilities;
        
        // Performance tracking
        std::map<std::string, std::vector<double>> m_execution_times;
        bool m_monitoring_enabled = false;
    };
}

#endif // MACOS_BUILD

// Template implementations for GCDParallelism
namespace lvk::ocl::macos
{
    template<typename Func>
    void GCDParallelism::parallel_for(size_t start, size_t end, Func&& func)
    {
        if (!m_available || end <= start)
            return;
        
        size_t range = end - start;
        size_t chunk_size = std::max(size_t(1), range / m_thread_count);
        
        dispatch_queue_t queue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0);
        dispatch_group_t group = dispatch_group_create();
        
        for (size_t i = start; i < end; i += chunk_size)
        {
            size_t chunk_end = std::min(i + chunk_size, end);
            
            dispatch_group_async(group, queue, ^{
                for (size_t j = i; j < chunk_end; ++j)
                {
                    func(j);
                }
            });
        }
        
        dispatch_group_wait(group, DISPATCH_TIME_FOREVER);
        dispatch_release(group);
    }
    
    template<typename Func>
    void GCDParallelism::parallel_for_2d(size_t width, size_t height, Func&& func)
    {
        if (!m_available || width == 0 || height == 0)
            return;
        
        size_t total_pixels = width * height;
        size_t chunk_size = std::max(size_t(1), total_pixels / m_thread_count);
        
        dispatch_queue_t queue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0);
        dispatch_group_t group = dispatch_group_create();
        
        for (size_t i = 0; i < total_pixels; i += chunk_size)
        {
            size_t chunk_end = std::min(i + chunk_size, total_pixels);
            
            dispatch_group_async(group, queue, ^{
                for (size_t j = i; j < chunk_end; ++j)
                {
                    size_t x = j % width;
                    size_t y = j / width;
                    func(x, y);
                }
            });
        }
        
        dispatch_group_wait(group, DISPATCH_TIME_FOREVER);
        dispatch_release(group);
    }
    
    template<typename Func>
    bool GPUAccelerationManager::execute_accelerated(const std::string& operation_type, Func&& operation)
    {
        if (!m_initialized)
            return false;
        
        AccelerationType best_method = get_best_acceleration(operation_type);
        
        auto start_time = std::chrono::high_resolution_clock::now();
        bool success = false;
        
        try
        {
            switch (best_method)
            {
                case AccelerationType::OPENCL:
                {
                    auto& opencl = MacOSOpenCLContext::instance();
                    success = opencl.try_gpu_operation(
                        [&]() { return operation(); },
                        [&]() { return operation(); } // CPU fallback
                    );
                    break;
                }
                
#ifdef MACOS_MPS_AVAILABLE
                case AccelerationType::METAL_MPS:
                {
                    // Try Metal first, fall back to CPU
                    success = operation();
                    break;
                }
#endif
                
                case AccelerationType::ACCELERATE:
                case AccelerationType::GCD_PARALLEL:
                case AccelerationType::CPU_FALLBACK:
                default:
                {
                    success = operation();
                    break;
                }
            }
        }
        catch (const std::exception& e)
        {
            success = false;
        }
        
        auto end_time = std::chrono::high_resolution_clock::now();
        
        if (m_monitoring_enabled)
        {
            auto duration = std::chrono::duration_cast<std::chrono::microseconds>(end_time - start_time);
            double execution_time_ms = duration.count() / 1000.0;
            m_execution_times[operation_type].push_back(execution_time_ms);
            
            // Keep only the last 100 measurements to avoid memory growth
            if (m_execution_times[operation_type].size() > 100)
            {
                m_execution_times[operation_type].erase(m_execution_times[operation_type].begin());
            }
        }
        
        return success;
    }
}