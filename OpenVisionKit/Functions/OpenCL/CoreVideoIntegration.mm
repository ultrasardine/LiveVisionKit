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

#include "CoreVideoIntegration.hpp"
#include "../../Directives.hpp"

#include <CoreVideo/CoreVideo.h>
#include <CoreFoundation/CoreFoundation.h>
#include <chrono>
#include <algorithm>

namespace lvk::corevideo
{

//---------------------------------------------------------------------------------------------------------------------
// PixelBufferManager Implementation
//---------------------------------------------------------------------------------------------------------------------

PixelBufferManager& PixelBufferManager::instance()
{
    static PixelBufferManager instance;
    return instance;
}

PixelBufferManager::~PixelBufferManager()
{
    release();
}

bool PixelBufferManager::initialize()
{
    if (m_initialized)
        return true;
    
    if (!setup_pixel_buffer_attributes())
        return false;
    
    m_initialized = true;
    return true;
}

void PixelBufferManager::release()
{
    if (m_initialized)
    {
        cleanup_pixel_buffer_attributes();
        m_initialized = false;
    }
}

bool PixelBufferManager::setup_pixel_buffer_attributes()
{
    // Create pixel buffer attributes for optimal performance
    CFMutableDictionaryRef attributes = CFDictionaryCreateMutable(
        kCFAllocatorDefault, 0,
        &kCFTypeDictionaryKeyCallBacks,
        &kCFTypeDictionaryValueCallBacks
    );
    
    if (!attributes)
        return false;
    
    // Enable hardware acceleration
    CFDictionarySetValue(attributes, kCVPixelBufferIOSurfacePropertiesKey, 
                        CFDictionaryCreate(kCFAllocatorDefault, nullptr, nullptr, 0,
                                         &kCFTypeDictionaryKeyCallBacks,
                                         &kCFTypeDictionaryValueCallBacks));
    
    // Set memory alignment for optimal performance
    int alignment = 32; // 32-byte alignment for SIMD operations
    CFNumberRef alignment_number = CFNumberCreate(kCFAllocatorDefault, kCFNumberIntType, &alignment);
    CFDictionarySetValue(attributes, kCVPixelBufferBytesPerRowAlignmentKey, alignment_number);
    CFRelease(alignment_number);
    
    m_pixel_buffer_attributes = attributes;
    return true;
}

void PixelBufferManager::cleanup_pixel_buffer_attributes()
{
    if (m_pixel_buffer_attributes)
    {
        CFRelease(m_pixel_buffer_attributes);
        m_pixel_buffer_attributes = nullptr;
    }
}

bool PixelBufferManager::mat_to_pixel_buffer(const cv::Mat& mat, CVPixelBufferRef& pixel_buffer)
{
    if (mat.empty())
        return false;
    
    OSType pixel_format = get_optimal_pixel_format(mat);
    
    CVReturn result = CVPixelBufferCreate(
        kCFAllocatorDefault,
        mat.cols,
        mat.rows,
        pixel_format,
        m_pixel_buffer_attributes,
        &pixel_buffer
    );
    
    if (result != kCVReturnSuccess)
        return false;
    
    // Lock the pixel buffer for writing
    CVPixelBufferLockBaseAddress(pixel_buffer, 0);
    
    void* base_address = CVPixelBufferGetBaseAddress(pixel_buffer);
    size_t bytes_per_row = CVPixelBufferGetBytesPerRow(pixel_buffer);
    
    // Copy data from OpenCV Mat to pixel buffer
    if (mat.isContinuous() && bytes_per_row == mat.step)
    {
        // Direct copy for continuous data
        memcpy(base_address, mat.data, mat.total() * mat.elemSize());
    }
    else
    {
        // Row-by-row copy for non-continuous data
        const uint8_t* src_data = mat.data;
        uint8_t* dst_data = static_cast<uint8_t*>(base_address);
        
        for (int row = 0; row < mat.rows; ++row)
        {
            memcpy(dst_data, src_data, mat.cols * mat.elemSize());
            src_data += mat.step;
            dst_data += bytes_per_row;
        }
    }
    
    CVPixelBufferUnlockBaseAddress(pixel_buffer, 0);
    return true;
}

bool PixelBufferManager::pixel_buffer_to_mat(CVPixelBufferRef pixel_buffer, cv::Mat& mat)
{
    if (!pixel_buffer)
        return false;
    
    CVPixelBufferLockBaseAddress(pixel_buffer, kCVPixelBufferLock_ReadOnly);
    
    size_t width = CVPixelBufferGetWidth(pixel_buffer);
    size_t height = CVPixelBufferGetHeight(pixel_buffer);
    size_t bytes_per_row = CVPixelBufferGetBytesPerRow(pixel_buffer);
    void* base_address = CVPixelBufferGetBaseAddress(pixel_buffer);
    
    OSType pixel_format = CVPixelBufferGetPixelFormatType(pixel_buffer);
    int opencv_type = utils::corevideo_to_opencv_format(pixel_format);
    
    if (opencv_type < 0)
    {
        CVPixelBufferUnlockBaseAddress(pixel_buffer, kCVPixelBufferLock_ReadOnly);
        return false;
    }
    
    // Create OpenCV Mat with the pixel buffer data
    mat = cv::Mat(static_cast<int>(height), static_cast<int>(width), opencv_type, 
                  base_address, bytes_per_row);
    
    // Make a copy to ensure data persistence after unlocking
    mat = mat.clone();
    
    CVPixelBufferUnlockBaseAddress(pixel_buffer, kCVPixelBufferLock_ReadOnly);
    return true;
}

CVPixelBufferPoolRef PixelBufferManager::create_pixel_buffer_pool(size_t width, size_t height, OSType pixel_format)
{
    CFMutableDictionaryRef pool_attributes = CFDictionaryCreateMutable(
        kCFAllocatorDefault, 0,
        &kCFTypeDictionaryKeyCallBacks,
        &kCFTypeDictionaryValueCallBacks
    );
    
    // Set minimum buffer count for the pool
    int min_buffer_count = 3;
    CFNumberRef min_count = CFNumberCreate(kCFAllocatorDefault, kCFNumberIntType, &min_buffer_count);
    CFDictionarySetValue(pool_attributes, kCVPixelBufferPoolMinimumBufferCountKey, min_count);
    CFRelease(min_count);
    
    // Create pixel buffer attributes
    CFMutableDictionaryRef pixel_attributes = CFDictionaryCreateMutable(
        kCFAllocatorDefault, 0,
        &kCFTypeDictionaryKeyCallBacks,
        &kCFTypeDictionaryValueCallBacks
    );
    
    CFNumberRef width_number = CFNumberCreate(kCFAllocatorDefault, kCFNumberSInt64Type, &width);
    CFNumberRef height_number = CFNumberCreate(kCFAllocatorDefault, kCFNumberSInt64Type, &height);
    CFNumberRef format_number = CFNumberCreate(kCFAllocatorDefault, kCFNumberSInt32Type, &pixel_format);
    
    CFDictionarySetValue(pixel_attributes, kCVPixelBufferWidthKey, width_number);
    CFDictionarySetValue(pixel_attributes, kCVPixelBufferHeightKey, height_number);
    CFDictionarySetValue(pixel_attributes, kCVPixelBufferPixelFormatTypeKey, format_number);
    
    CFRelease(width_number);
    CFRelease(height_number);
    CFRelease(format_number);
    
    // Add IOSurface support for hardware acceleration
    CFDictionarySetValue(pixel_attributes, kCVPixelBufferIOSurfacePropertiesKey,
                        CFDictionaryCreate(kCFAllocatorDefault, nullptr, nullptr, 0,
                                         &kCFTypeDictionaryKeyCallBacks,
                                         &kCFTypeDictionaryValueCallBacks));
    
    CVPixelBufferPoolRef pool = nullptr;
    CVReturn result = CVPixelBufferPoolCreate(kCFAllocatorDefault, pool_attributes, 
                                            pixel_attributes, &pool);
    
    CFRelease(pool_attributes);
    CFRelease(pixel_attributes);
    
    return (result == kCVReturnSuccess) ? pool : nullptr;
}

OSType PixelBufferManager::get_optimal_pixel_format(const cv::Mat& mat) const
{
    switch (mat.type())
    {
        case CV_8UC3:
            return kCVPixelFormatType_24RGB;
        case CV_8UC4:
            return kCVPixelFormatType_32ARGB;
        case CV_8UC1:
            return kCVPixelFormatType_OneComponent8;
        case CV_16UC1:
            return kCVPixelFormatType_OneComponent16Half;
        case CV_32FC1:
            return kCVPixelFormatType_OneComponent32Float;
        default:
            return kCVPixelFormatType_24RGB; // Default fallback
    }
}

//---------------------------------------------------------------------------------------------------------------------
// DisplayLinkManager Implementation
//---------------------------------------------------------------------------------------------------------------------

DisplayLinkManager& DisplayLinkManager::instance()
{
    static DisplayLinkManager instance;
    return instance;
}

DisplayLinkManager::~DisplayLinkManager()
{
    release();
}

bool DisplayLinkManager::initialize()
{
    if (m_initialized)
        return true;
    
    if (!setup_display_link())
        return false;
    
    m_initialized = true;
    return true;
}

void DisplayLinkManager::release()
{
    if (m_initialized)
    {
        stop_display_sync();
        cleanup_display_link();
        m_initialized = false;
    }
}

bool DisplayLinkManager::setup_display_link()
{
    CVReturn result = CVDisplayLinkCreateWithActiveCGDisplays(&m_display_link);
    if (result != kCVReturnSuccess)
        return false;
    
    result = CVDisplayLinkSetOutputCallback(m_display_link, &DisplayLinkManager::display_link_callback, this);
    return (result == kCVReturnSuccess);
}

void DisplayLinkManager::cleanup_display_link()
{
    if (m_display_link)
    {
        CVDisplayLinkRelease(m_display_link);
        m_display_link = nullptr;
    }
}

CVReturn DisplayLinkManager::display_link_callback(CVDisplayLinkRef display_link,
                                                 const CVTimeStamp* now,
                                                 const CVTimeStamp* output_time,
                                                 CVOptionFlags flags_in,
                                                 CVOptionFlags* flags_out,
                                                 void* display_link_context)
{
    DisplayLinkManager* manager = static_cast<DisplayLinkManager*>(display_link_context);
    
    if (manager && manager->m_callback)
    {
        double frame_time = static_cast<double>(output_time->videoTime) / output_time->videoTimeScale;
        manager->m_callback(frame_time);
    }
    
    return kCVReturnSuccess;
}

bool DisplayLinkManager::start_display_sync(std::function<void(double)> callback)
{
    if (!m_initialized || !m_display_link)
        return false;
    
    m_callback = callback;
    CVReturn result = CVDisplayLinkStart(m_display_link);
    return (result == kCVReturnSuccess);
}

void DisplayLinkManager::stop_display_sync()
{
    if (m_display_link && CVDisplayLinkIsRunning(m_display_link))
    {
        CVDisplayLinkStop(m_display_link);
    }
    m_callback = nullptr;
}

double DisplayLinkManager::get_display_refresh_rate() const
{
    if (!m_display_link)
        return 60.0; // Default fallback
    
    CVTime time = CVDisplayLinkGetNominalOutputVideoRefreshPeriod(m_display_link);
    if (time.timeScale == 0)
        return 60.0;
    
    return static_cast<double>(time.timeScale) / time.timeValue;
}

double DisplayLinkManager::get_display_frame_duration() const
{
    double refresh_rate = get_display_refresh_rate();
    return (refresh_rate > 0) ? (1.0 / refresh_rate) : (1.0 / 60.0);
}

//---------------------------------------------------------------------------------------------------------------------
// Utility Functions Implementation
//---------------------------------------------------------------------------------------------------------------------

namespace utils
{
    OSType opencv_to_corevideo_format(int opencv_type)
    {
        switch (opencv_type)
        {
            case CV_8UC3:
                return kCVPixelFormatType_24RGB;
            case CV_8UC4:
                return kCVPixelFormatType_32ARGB;
            case CV_8UC1:
                return kCVPixelFormatType_OneComponent8;
            case CV_16UC1:
                return kCVPixelFormatType_OneComponent16Half;
            case CV_32FC1:
                return kCVPixelFormatType_OneComponent32Float;
            default:
                return 0; // Invalid format
        }
    }
    
    int corevideo_to_opencv_format(OSType cv_format)
    {
        switch (cv_format)
        {
            case kCVPixelFormatType_24RGB:
                return CV_8UC3;
            case kCVPixelFormatType_32ARGB:
                return CV_8UC4;
            case kCVPixelFormatType_OneComponent8:
                return CV_8UC1;
            case kCVPixelFormatType_OneComponent16Half:
                return CV_16UC1;
            case kCVPixelFormatType_OneComponent32Float:
                return CV_32FC1;
            default:
                return -1; // Invalid format
        }
    }
    
    std::string corevideo_error_to_string(CVReturn error)
    {
        switch (error)
        {
            case kCVReturnSuccess:
                return "Success";
            case kCVReturnError:
                return "Generic error";
            case kCVReturnInvalidArgument:
                return "Invalid argument";
            case kCVReturnAllocationFailed:
                return "Allocation failed";
            case kCVReturnUnsupported:
                return "Unsupported operation";
            case kCVReturnInvalidDisplay:
                return "Invalid display";
            case kCVReturnDisplayLinkAlreadyRunning:
                return "Display link already running";
            case kCVReturnDisplayLinkNotRunning:
                return "Display link not running";
            case kCVReturnDisplayLinkCallbacksNotSet:
                return "Display link callbacks not set";
            default:
                return "Unknown error (" + std::to_string(error) + ")";
        }
    }
    
    bool check_corevideo_error(CVReturn error, const std::string& operation)
    {
        if (error == kCVReturnSuccess)
            return true;
        
        // In a real implementation, this would use the LVK logging system
        // For now, we'll just return false to indicate failure
        return false;
    }
    
    PerformanceTimer::PerformanceTimer(const std::string& operation_name)
        : m_operation_name(operation_name)
    {
        start();
    }
    
    PerformanceTimer::~PerformanceTimer()
    {
        if (m_running)
        {
            stop();
            // In a real implementation, this would log the performance data
        }
    }
    
    void PerformanceTimer::start()
    {
        m_start_time = std::chrono::high_resolution_clock::now();
        m_running = true;
    }
    
    void PerformanceTimer::stop()
    {
        if (m_running)
        {
            m_end_time = std::chrono::high_resolution_clock::now();
            m_running = false;
        }
    }
    
    double PerformanceTimer::get_elapsed_ms() const
    {
        auto end_time = m_running ? std::chrono::high_resolution_clock::now() : m_end_time;
        auto duration = std::chrono::duration_cast<std::chrono::microseconds>(end_time - m_start_time);
        return duration.count() / 1000.0;
    }
    
    bool is_valid_pixel_format(OSType format)
    {
        switch (format)
        {
            case kCVPixelFormatType_24RGB:
            case kCVPixelFormatType_32ARGB:
            case kCVPixelFormatType_OneComponent8:
            case kCVPixelFormatType_OneComponent16Half:
            case kCVPixelFormatType_OneComponent32Float:
            case kCVPixelFormatType_420YpCbCr8Planar:
            case kCVPixelFormatType_422YpCbCr8:
                return true;
            default:
                return false;
        }
    }
    
    bool is_supported_resolution(size_t width, size_t height)
    {
        // Check for reasonable resolution limits
        return (width >= 1 && width <= 8192 && height >= 1 && height <= 8192);
    }
    
    void print_pixel_buffer_info(CVPixelBufferRef buffer)
    {
        if (!buffer)
            return;
        
        size_t width = CVPixelBufferGetWidth(buffer);
        size_t height = CVPixelBufferGetHeight(buffer);
        OSType format = CVPixelBufferGetPixelFormatType(buffer);
        size_t bytes_per_row = CVPixelBufferGetBytesPerRow(buffer);
        
        // In a real implementation, this would use the LVK logging system
        // For now, we'll just validate the buffer properties
    }
    
    bool validate_pixel_buffer(CVPixelBufferRef buffer)
    {
        if (!buffer)
            return false;
        
        size_t width = CVPixelBufferGetWidth(buffer);
        size_t height = CVPixelBufferGetHeight(buffer);
        OSType format = CVPixelBufferGetPixelFormatType(buffer);
        
        return is_supported_resolution(width, height) && is_valid_pixel_format(format);
    }
}

} // namespace lvk::corevideo

#endif // MACOS_BUILD