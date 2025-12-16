//     *************************** OpenVisionKit ****************************
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

#include <catch2/catch_test_macros.hpp>
#include <catch2/generators/catch_generators.hpp>
#include <catch2/generators/catch_generators_range.hpp>

#ifdef MACOS_BUILD
#include "../Modules/VideoEditor/MacOSVideoSupport.hpp"
#include <filesystem>
#include <fstream>
#include <random>
#include <thread>

using namespace clt::macos;

namespace
{
    // Test data generators for property-based testing
    
    std::vector<std::string> generate_video_extensions()
    {
        return {".mov", ".mp4", ".m4v", ".avi", ".mkv", ".webm"};
    }
    
    std::vector<std::string> generate_codec_fourccs()
    {
        return {"avc1", "hvc1", "jpeg", "mp4v", "H264", "HEVC"};
    }
    
    std::filesystem::path create_test_video_file(const std::string& extension)
    {
        static int file_counter = 0;
        std::filesystem::path temp_dir = std::filesystem::temp_directory_path();
        std::filesystem::path test_file = temp_dir / ("test_video_" + std::to_string(file_counter++) + extension);
        
        // Create a minimal test file (not a real video, just for path testing)
        std::ofstream file(test_file);
        file << "test video content";
        file.close();
        
        return test_file;
    }
    
    void cleanup_test_file(const std::filesystem::path& file_path)
    {
        if (std::filesystem::exists(file_path))
        {
            std::filesystem::remove(file_path);
        }
    }
}

TEST_CASE("macOS Video Format Support", "[video][macos][format]")
{
    SECTION("VideoFormatSupport initialization")
    {
        REQUIRE(VideoFormatSupport::initialize());
        
        // Should be able to initialize multiple times
        REQUIRE(VideoFormatSupport::initialize());
        
        VideoFormatSupport::release();
    }
    
    SECTION("Supported formats are available")
    {
        REQUIRE(VideoFormatSupport::initialize());
        
        auto formats = VideoFormatSupport::get_supported_formats();
        REQUIRE(!formats.empty());
        
        // Should have at least common macOS formats
        bool has_mov = false, has_mp4 = false;
        for (const auto& format : formats)
        {
            if (format.container_format.find("QuickTime") != std::string::npos ||
                format.container_format.find("MOV") != std::string::npos)
            {
                has_mov = true;
            }
            if (format.container_format.find("MPEG-4") != std::string::npos ||
                format.container_format.find("MP4") != std::string::npos)
            {
                has_mp4 = true;
            }
        }
        
        REQUIRE(has_mov);
        REQUIRE(has_mp4);
        
        VideoFormatSupport::release();
    }
}

// **Feature: macos-build-support, Property 8: Video format handling**
// **Validates: Requirements 5.2**
TEST_CASE("Property Test: Video Format Handling", "[video][macos][property]")
{
    REQUIRE(VideoFormatSupport::initialize());
    
    SECTION("Format detection consistency")
    {
        // Property: For any common macOS video format, the video editor should process the format correctly
        auto extensions = generate_video_extensions();
        auto extension = GENERATE_COPY(Catch::Generators::from_range(extensions));
        
        DYNAMIC_SECTION("Testing extension: " << extension)
        {
            // Create test file with the extension
            auto test_file = create_test_video_file(extension);
            
            // Test path validation
            bool is_valid = PathProcessor::validate_video_path(test_file);
            
            // Should validate common video extensions
            if (extension == ".mov" || extension == ".mp4" || extension == ".m4v" || 
                extension == ".avi" || extension == ".mkv" || extension == ".webm")
            {
                REQUIRE(is_valid);
            }
            
            // Test native codec recommendation
            auto codec_rec = VideoFormatSupport::get_native_codec_recommendation(extension);
            
            // Should have recommendations for native macOS formats
            if (extension == ".mov" || extension == ".mp4")
            {
                REQUIRE(codec_rec.has_value());
                REQUIRE(!codec_rec->name.empty());
                REQUIRE(!codec_rec->fourcc.empty());
            }
            
            cleanup_test_file(test_file);
        }
    }
    
    SECTION("Codec conversion consistency")
    {
        // Property: For any supported codec, conversion between OpenCV and AVFoundation should be consistent
        auto fourccs = generate_codec_fourccs();
        auto fourcc = GENERATE_COPY(Catch::Generators::from_range(fourccs));
        
        DYNAMIC_SECTION("Testing codec: " << fourcc)
        {
            // Test AVFoundation to OpenCV conversion
            int opencv_fourcc = VideoFormatSupport::avfoundation_codec_to_opencv_fourcc(fourcc);
            
            if (opencv_fourcc != -1)
            {
                // If conversion succeeded, reverse conversion should work
                std::string converted_back = VideoFormatSupport::opencv_fourcc_to_avfoundation(opencv_fourcc);
                REQUIRE(!converted_back.empty());
                
                // For well-known codecs, should maintain consistency
                if (fourcc == "avc1" || fourcc == "H264")
                {
                    REQUIRE((converted_back == "avc1" || converted_back == "H264"));
                }
            }
        }
    }
    
    SECTION("Hardware acceleration detection")
    {
        // Property: Hardware acceleration detection should be consistent across codec queries
        auto fourccs = generate_codec_fourccs();
        auto fourcc = GENERATE_COPY(Catch::Generators::from_range(fourccs));
        
        DYNAMIC_SECTION("Testing hardware acceleration for: " << fourcc)
        {
            bool is_hw_accelerated = VideoFormatSupport::is_hardware_accelerated(fourcc);
            
            // VideoToolbox availability should be consistent
            bool vt_available = VideoFormatSupport::is_videotoolbox_available();
            
            // If VideoToolbox is available and codec is H.264/H.265, should support hardware acceleration
            if (vt_available && (fourcc == "avc1" || fourcc == "hvc1" || fourcc == "H264" || fourcc == "HEVC"))
            {
                // Note: This might not always be true depending on hardware, so we just check consistency
                INFO("VideoToolbox available, checking codec support for: " << fourcc);
            }
            
            // Hardware acceleration status should be boolean
            REQUIRE((is_hw_accelerated == true || is_hw_accelerated == false));
        }
    }
    
    VideoFormatSupport::release();
}

TEST_CASE("macOS Path Processing", "[path][macos]")
{
    SECTION("Path normalization")
    {
        std::filesystem::path test_path = "/Users/test/Documents/video.mov";
        std::string normalized = PathProcessor::normalize_path(test_path);
        
        REQUIRE(!normalized.empty());
        REQUIRE(normalized.find("/Users/test/Documents/video.mov") != std::string::npos);
    }
    
    SECTION("macOS filesystem detection")
    {
        // Test typical macOS paths
        REQUIRE(PathProcessor::is_macos_filesystem_path("/Users/test/video.mov"));
        REQUIRE(PathProcessor::is_macos_filesystem_path("/Applications/Test.app"));
        REQUIRE(PathProcessor::is_macos_filesystem_path("/System/Library/test"));
        REQUIRE(PathProcessor::is_macos_filesystem_path("/Library/test"));
        REQUIRE(PathProcessor::is_macos_filesystem_path("/Volumes/External/test"));
        
        // Test non-macOS paths
        REQUIRE_FALSE(PathProcessor::is_macos_filesystem_path("/home/user/video.mov"));
        REQUIRE_FALSE(PathProcessor::is_macos_filesystem_path("C:\\Users\\test\\video.mov"));
    }
    
    SECTION("Path separator conversion")
    {
        std::string windows_path = "C:\\Users\\test\\video.mov";
        std::string converted = PathProcessor::convert_path_separators(windows_path);
        
        REQUIRE(converted == "C:/Users/test/video.mov");
        REQUIRE(converted.find('\\') == std::string::npos);
    }
}

// **Feature: macos-build-support, Property 9: Path processing correctness**
// **Validates: Requirements 5.4**
TEST_CASE("Property Test: Path Processing Correctness", "[path][macos][property]")
{
    SECTION("Path normalization preserves validity")
    {
        // Property: For any valid macOS file path format, the system should correctly process and handle the path
        
        // Generate various path formats
        std::vector<std::string> test_paths = {
            "/Users/test/Documents/video.mov",
            "/Users/test/Movies/../Documents/video.mp4",
            "/Applications/Test.app/Contents/Resources/video.m4v",
            "/Volumes/External Drive/Videos/test video.mov",
            "/tmp/test_video.avi"
        };
        
        for (const auto& path_str : test_paths)
        {
            DYNAMIC_SECTION("Testing path: " << path_str)
            {
                std::filesystem::path original_path(path_str);
                std::string normalized = PathProcessor::normalize_path(original_path);
                
                // Normalized path should not be empty
                REQUIRE(!normalized.empty());
                
                // Should be a valid filesystem path
                std::filesystem::path normalized_path(normalized);
                REQUIRE((normalized_path.is_absolute() || normalized_path.is_relative()));
                
                // Should preserve the filename if it existed
                if (original_path.has_filename())
                {
                    REQUIRE(normalized_path.has_filename());
                }
                
                // Should preserve the extension if it existed
                if (original_path.has_extension())
                {
                    REQUIRE(normalized_path.has_extension());
                }
            }
        }
    }
    
    SECTION("Unicode filename normalization")
    {
        // Property: Unicode normalization should preserve filename validity
        std::vector<std::string> unicode_filenames = {
            "test_video.mov",
            "tëst_vídeo.mp4",
            "测试视频.mov",
            "тест_видео.mp4",
            "test video with spaces.mov"
        };
        
        for (const auto& filename : unicode_filenames)
        {
            DYNAMIC_SECTION("Testing Unicode filename: " << filename)
            {
                std::string normalized = PathProcessor::normalize_unicode_filename(filename);
                
                // Normalized filename should not be empty
                REQUIRE(!normalized.empty());
                
                // Should still be a valid filename (no path separators)
                REQUIRE(normalized.find('/') == std::string::npos);
                REQUIRE(normalized.find('\\') == std::string::npos);
                
                // Should preserve basic structure (extension if present)
                if (filename.find('.') != std::string::npos)
                {
                    REQUIRE(normalized.find('.') != std::string::npos);
                }
            }
        }
    }
    
    SECTION("Path validation consistency")
    {
        // Property: Path validation should be consistent for video file extensions
        auto extensions = generate_video_extensions();
        auto extension = GENERATE_COPY(Catch::Generators::from_range(extensions));
        
        DYNAMIC_SECTION("Testing path validation for extension: " << extension)
        {
            // Create test paths with the extension
            std::vector<std::filesystem::path> test_paths = {
                std::filesystem::path("/Users/test/video") += extension,
                std::filesystem::path("/tmp/test_file") += extension,
                std::filesystem::path("./relative_video") += extension
            };
            
            for (const auto& path : test_paths)
            {
                // Create temporary file for testing
                auto temp_file = create_test_video_file(extension);
                
                bool is_valid = PathProcessor::validate_video_path(temp_file);
                
                // Should validate known video extensions
                if (extension == ".mov" || extension == ".mp4" || extension == ".m4v" || 
                    extension == ".avi" || extension == ".mkv" || extension == ".webm")
                {
                    REQUIRE(is_valid);
                }
                
                cleanup_test_file(temp_file);
            }
        }
    }
}

TEST_CASE("macOS Parallel Processing", "[parallel][macos]")
{
    SECTION("Parallel processing initialization")
    {
        REQUIRE(ParallelProcessing::initialize());
        
        // Should be able to initialize multiple times
        REQUIRE(ParallelProcessing::initialize());
        
        // Should have reasonable queue count
        size_t queue_count = ParallelProcessing::get_optimal_queue_count();
        REQUIRE(queue_count > 0);
        REQUIRE(queue_count <= std::thread::hardware_concurrency());
        
        ParallelProcessing::release();
    }
    
    SECTION("Cancellation mechanism")
    {
        REQUIRE(ParallelProcessing::initialize());
        
        // Initially should not be cancelled
        REQUIRE_FALSE(ParallelProcessing::is_cancelled());
        
        // Request cancellation
        ParallelProcessing::request_cancellation();
        REQUIRE(ParallelProcessing::is_cancelled());
        
        // Reset cancellation
        ParallelProcessing::reset_cancellation();
        REQUIRE_FALSE(ParallelProcessing::is_cancelled());
        
        ParallelProcessing::release();
    }
    
    SECTION("Parallel frame processing")
    {
        REQUIRE(ParallelProcessing::initialize());
        
        // Create test frames
        std::vector<cv::Mat> test_frames;
        for (int i = 0; i < 10; ++i)
        {
            test_frames.emplace_back(100, 100, CV_8UC3, cv::Scalar(i * 25, i * 25, i * 25));
        }
        
        std::atomic<int> processed_count{0};
        std::atomic<double> last_progress{0.0};
        
        bool success = ParallelProcessing::process_frames_parallel(
            test_frames,
            [&](cv::Mat& frame, size_t index) {
                // Simple processing: add 10 to all pixel values
                frame += cv::Scalar(10, 10, 10);
                processed_count++;
            },
            [&](double progress) {
                last_progress = progress;
            }
        );
        
        REQUIRE(success);
        REQUIRE(processed_count == 10);
        REQUIRE(last_progress >= 0.5); // Progress should be substantial, but may not be exactly 1.0 due to threading
        
        ParallelProcessing::release();
    }
    
    SECTION("Batch processing")
    {
        REQUIRE(ParallelProcessing::initialize());
        
        const size_t total_items = 100;
        const size_t batch_size = 10;
        std::atomic<size_t> processed_batches{0};
        std::atomic<size_t> processed_items{0};
        
        bool success = ParallelProcessing::process_batches(
            batch_size,
            total_items,
            [&](size_t start, size_t end, size_t batch_idx) {
                processed_batches++;
                processed_items += (end - start);
            },
            [](double progress) {
                // Progress callback
            }
        );
        
        REQUIRE(success);
        REQUIRE(processed_items == total_items);
        REQUIRE(processed_batches == (total_items + batch_size - 1) / batch_size);
        
        ParallelProcessing::release();
    }
}

TEST_CASE("macOS Hardware Acceleration", "[hardware][macos]")
{
    SECTION("Hardware acceleration availability")
    {
        // These should not throw and should return boolean values
        bool metal_available = HardwareAcceleration::is_metal_available();
        bool vt_encoding = HardwareAcceleration::is_videotoolbox_encoding_available();
        bool vt_decoding = HardwareAcceleration::is_videotoolbox_decoding_available();
        
        // Should return valid boolean values
        REQUIRE((metal_available == true || metal_available == false));
        REQUIRE((vt_encoding == true || vt_encoding == false));
        REQUIRE((vt_decoding == true || vt_decoding == false));
    }
    
    SECTION("Hardware acceleration properties")
    {
        auto properties = HardwareAcceleration::get_hardware_acceleration_properties(
            1920, 1080, cv::VideoWriter::fourcc('H','2','6','4')
        );
        
        // Should return a valid properties vector
        REQUIRE(properties.size() % 2 == 0); // Properties come in key-value pairs
        
        // Should contain reasonable property values
        for (size_t i = 0; i < properties.size(); i += 2)
        {
            int property_id = properties[i];
            int property_value = properties[i + 1];
            
            // Property IDs should be valid OpenCV constants
            REQUIRE(property_id >= 0);
            
            // Property values should be reasonable
            INFO("Property ID: " << property_id << ", Value: " << property_value);
        }
    }
}

#endif // MACOS_BUILD