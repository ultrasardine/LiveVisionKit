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
#include <CoreVideo/CoreVideo.h>
#include <CoreFoundation/CoreFoundation.h>

namespace lvk::corevideo
{
    // Core Video pixel buffer utilities for efficient video processing
    class PixelBufferManager
    {
    public:
        static PixelBufferManager& instance();
        
        bool initialize();
        void release();
        
        // Convert between OpenCV Mat and CVPixelBuffer for zero-copy operations
        bool mat_to_pixel_buffer(const cv::Mat& mat, CVPixelBufferRef& pixel_buffer);
        bool pixel_buffer_to_mat(CVPixelBufferRef pixel_buffer, cv::Mat& mat);
        
        // Create optimized pixel buffer pools for video processing
        CVPixelBufferPoolRef create_pixel_buffer_pool(size_t width, size_t height, 
                                                     OSType pixel_format = kCVPixelFormatType_24RGB);
        
        // Hardware-accelerated format conversions
        bool convert_yuv_to_rgb(CVPixelBufferRef yuv_buffer, CVPixelBufferRef rgb_buffer);
        bool convert_rgb_to_yuv(CVPixelBufferRef rgb_buffer, CVPixelBufferRef yuv_buffer);
        
        // Memory-efficient buffer operations
        bool copy_pixel_buffer(CVPixelBufferRef source, CVPixelBufferRef destination);
        bool resize_pixel_buffer(CVPixelBufferRef source, CVPixelBufferRef destination);
        
        // Get optimal pixel format for processing
        OSType get_optimal_pixel_format(const cv::Mat& mat) const;
        
    private:
        PixelBufferManager() = default;
        ~PixelBufferManager();
        
        bool m_initialized = false;
        CFDictionaryRef m_pixel_buffer_attributes = nullptr;
        
        bool setup_pixel_buffer_attributes();
        void cleanup_pixel_buffer_attributes();
    };
    
    // Core Video display link for synchronized video processing
    class DisplayLinkManager
    {
    public:
        static DisplayLinkManager& instance();
        
        bool initialize();
        void release();
        
        // Synchronize video processing with display refresh rate
        bool start_display_sync(std::function<void(double)> callback);
        void stop_display_sync();
        
        // Get display refresh rate information
        double get_display_refresh_rate() const;
        double get_display_frame_duration() const;
        
        // Adaptive frame rate control
        void set_target_frame_rate(double fps);
        double get_target_frame_rate() const;
        
    private:
        DisplayLinkManager() = default;
        ~DisplayLinkManager();
        
        bool m_initialized = false;
        CVDisplayLinkRef m_display_link = nullptr;
        std::function<void(double)> m_callback;
        double m_target_fps = 60.0;
        
        static CVReturn display_link_callback(CVDisplayLinkRef display_link,
                                            const CVTimeStamp* now,
                                            const CVTimeStamp* output_time,
                                            CVOptionFlags flags_in,
                                            CVOptionFlags* flags_out,
                                            void* display_link_context);
        
        bool setup_display_link();
        void cleanup_display_link();
    };
    
    // Hardware-accelerated video format utilities
    class VideoFormatOptimizer
    {
    public:
        static VideoFormatOptimizer& instance();
        
        bool initialize();
        void release();
        
        // Optimize video format for hardware acceleration
        struct OptimalFormat
        {
            OSType pixel_format;
            size_t width;
            size_t height;
            bool hardware_accelerated;
            bool zero_copy_supported;
        };
        
        OptimalFormat get_optimal_format(size_t input_width, size_t input_height, 
                                       OSType input_format) const;
        
        // Check hardware acceleration capabilities
        bool supports_hardware_decode(OSType codec_type) const;
        bool supports_hardware_encode(OSType codec_type) const;
        
        // Memory alignment optimization
        size_t get_optimal_row_bytes(size_t width, OSType pixel_format) const;
        size_t get_optimal_buffer_size(size_t width, size_t height, OSType pixel_format) const;
        
        // Format conversion utilities
        bool is_planar_format(OSType pixel_format) const;
        bool is_rgb_format(OSType pixel_format) const;
        bool is_yuv_format(OSType pixel_format) const;
        
        // Get format information
        size_t get_bytes_per_pixel(OSType pixel_format) const;
        size_t get_plane_count(OSType pixel_format) const;
        
    private:
        VideoFormatOptimizer() = default;
        
        bool m_initialized = false;
        
        struct FormatInfo
        {
            OSType format;
            size_t bytes_per_pixel;
            size_t plane_count;
            bool is_planar;
            bool is_rgb;
            bool is_yuv;
            bool hardware_supported;
        };
        
        std::vector<FormatInfo> m_supported_formats;
        
        void initialize_format_database();
    };
    
    // Core Video memory pool for efficient buffer management
    class MemoryPoolManager
    {
    public:
        static MemoryPoolManager& instance();
        
        bool initialize();
        void release();
        
        // Create and manage pixel buffer pools
        CVPixelBufferPoolRef get_or_create_pool(size_t width, size_t height, 
                                              OSType pixel_format, size_t pool_size = 10);
        
        // Pool statistics and management
        size_t get_pool_count() const;
        size_t get_total_allocated_memory() const;
        void cleanup_unused_pools();
        
        // Memory pressure handling
        void handle_memory_pressure();
        void set_memory_pressure_callback(std::function<void(size_t)> callback);
        
    private:
        MemoryPoolManager() = default;
        ~MemoryPoolManager();
        
        bool m_initialized = false;
        
        struct PoolInfo
        {
            CVPixelBufferPoolRef pool;
            size_t width;
            size_t height;
            OSType pixel_format;
            size_t allocated_buffers;
            std::chrono::steady_clock::time_point last_used;
        };
        
        std::vector<PoolInfo> m_pools;
        std::function<void(size_t)> m_memory_pressure_callback;
        
        void cleanup_pool(size_t index);
        size_t calculate_pool_memory_usage(const PoolInfo& pool) const;
    };
    
    // Utility functions for Core Video integration
    namespace utils
    {
        // Convert OpenCV color space to Core Video pixel format
        OSType opencv_to_corevideo_format(int opencv_type);
        int corevideo_to_opencv_format(OSType cv_format);
        
        // Error handling utilities
        std::string corevideo_error_to_string(CVReturn error);
        bool check_corevideo_error(CVReturn error, const std::string& operation);
        
        // Performance measurement utilities
        class PerformanceTimer
        {
        public:
            PerformanceTimer(const std::string& operation_name);
            ~PerformanceTimer();
            
            void start();
            void stop();
            double get_elapsed_ms() const;
            
        private:
            std::string m_operation_name;
            std::chrono::high_resolution_clock::time_point m_start_time;
            std::chrono::high_resolution_clock::time_point m_end_time;
            bool m_running = false;
        };
        
        // Memory usage tracking
        size_t get_corevideo_memory_usage();
        void log_memory_usage(const std::string& context);
        
        // Format validation
        bool is_valid_pixel_format(OSType format);
        bool is_supported_resolution(size_t width, size_t height);
        
        // Buffer inspection utilities
        void print_pixel_buffer_info(CVPixelBufferRef buffer);
        bool validate_pixel_buffer(CVPixelBufferRef buffer);
    }
}

#endif // MACOS_BUILD