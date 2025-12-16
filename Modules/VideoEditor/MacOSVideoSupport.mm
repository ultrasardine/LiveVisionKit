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

#ifdef MACOS_BUILD

#include "MacOSVideoSupport.hpp"

#import <AVFoundation/AVFoundation.h>
#import <VideoToolbox/VideoToolbox.h>
#import <CoreFoundation/CoreFoundation.h>
#import <Foundation/Foundation.h>

#include <algorithm>
#include <unordered_map>
#include <locale>
#include <codecvt>
#include <atomic>
#include <thread>
#include <dispatch/dispatch.h>

namespace clt::macos
{

//---------------------------------------------------------------------------------------------------------------------
// VideoFormatSupport Implementation
//---------------------------------------------------------------------------------------------------------------------

bool VideoFormatSupport::m_initialized = false;
std::vector<VideoFormatSupport::FormatInfo> VideoFormatSupport::m_supported_formats;
std::vector<VideoFormatSupport::CodecInfo> VideoFormatSupport::m_videotoolbox_codecs;

bool VideoFormatSupport::initialize()
{
    if (m_initialized)
        return true;

    @autoreleasepool {
        initialize_supported_formats();
        initialize_videotoolbox_codecs();
        query_avfoundation_capabilities();
    }

    m_initialized = true;
    return true;
}

void VideoFormatSupport::release()
{
    if (m_initialized)
    {
        m_supported_formats.clear();
        m_videotoolbox_codecs.clear();
        m_initialized = false;
    }
}

std::optional<VideoFormatSupport::FormatInfo> VideoFormatSupport::detect_format(const std::filesystem::path& file_path)
{
    if (!m_initialized)
        initialize();

    @autoreleasepool {
        NSString* path_string = [NSString stringWithUTF8String:file_path.c_str()];
        NSURL* file_url = [NSURL fileURLWithPath:path_string];
        
        AVURLAsset* asset = [AVURLAsset URLAssetWithURL:file_url options:nil];
        if (!asset)
            return std::nullopt;

        // Get container format
        NSString* file_type = [asset valueForKey:@"naturalTimeScale"] ? @"mov" : @"mp4";
        std::string container_format = [file_type UTF8String];

        FormatInfo format_info;
        format_info.container_format = container_format;
        format_info.extensions = {file_path.extension().string()};
        format_info.hardware_accelerated = false;

        // Get video tracks and codec information
        NSArray<AVAssetTrack*>* video_tracks = [asset tracksWithMediaType:AVMediaTypeVideo];
        for (AVAssetTrack* track in video_tracks)
        {
            NSArray<NSString*>* format_descriptions = track.formatDescriptions;
            for (id format_desc in format_descriptions)
            {
                CMFormatDescriptionRef desc = (__bridge CMFormatDescriptionRef)format_desc;
                FourCharCode codec_type = CMFormatDescriptionGetMediaSubType(desc);
                
                CodecInfo codec_info;
                codec_info.fourcc = std::string(reinterpret_cast<const char*>(&codec_type), 4);
                codec_info.hardware_accelerated = is_hardware_accelerated(codec_info.fourcc);
                codec_info.supports_decoding = true;
                codec_info.supports_encoding = codec_info.hardware_accelerated;
                codec_info.supported_extensions = {file_path.extension().string()};

                // Map common codec types to names
                switch (codec_type)
                {
                    case kCMVideoCodecType_H264:
                        codec_info.name = "H.264";
                        break;
                    case kCMVideoCodecType_HEVC:
                        codec_info.name = "H.265/HEVC";
                        break;
                    case kCMVideoCodecType_AppleProRes422:
                        codec_info.name = "Apple ProRes 422";
                        break;
                    case kCMVideoCodecType_AppleProRes4444:
                        codec_info.name = "Apple ProRes 4444";
                        break;
                    default:
                        codec_info.name = "Unknown (" + codec_info.fourcc + ")";
                        break;
                }

                format_info.supported_codecs.push_back(codec_info);
                if (codec_info.hardware_accelerated)
                    format_info.hardware_accelerated = true;
            }
        }

        return format_info;
    }
}

std::vector<VideoFormatSupport::FormatInfo> VideoFormatSupport::get_supported_formats()
{
    if (!m_initialized)
        initialize();

    return m_supported_formats;
}

std::optional<VideoFormatSupport::CodecInfo> VideoFormatSupport::get_optimal_codec(const FormatInfo& format_info, bool prefer_hardware)
{
    if (format_info.supported_codecs.empty())
        return std::nullopt;

    // Find the best codec based on preferences
    const CodecInfo* best_codec = nullptr;
    
    for (const auto& codec : format_info.supported_codecs)
    {
        if (!best_codec)
        {
            best_codec = &codec;
            continue;
        }

        // Prefer hardware acceleration if requested
        if (prefer_hardware && codec.hardware_accelerated && !best_codec->hardware_accelerated)
        {
            best_codec = &codec;
            continue;
        }

        // Prefer codecs that support both encoding and decoding
        if (codec.supports_encoding && codec.supports_decoding && 
            (!best_codec->supports_encoding || !best_codec->supports_decoding))
        {
            best_codec = &codec;
            continue;
        }
    }

    return best_codec ? *best_codec : std::optional<CodecInfo>{};
}

bool VideoFormatSupport::is_hardware_accelerated(const std::string& fourcc)
{
    if (!m_initialized)
        initialize();

    // Check if codec is in VideoToolbox supported list
    for (const auto& codec : m_videotoolbox_codecs)
    {
        if (codec.fourcc == fourcc && codec.hardware_accelerated)
            return true;
    }

    return false;
}

std::optional<VideoFormatSupport::CodecInfo> VideoFormatSupport::get_native_codec_recommendation(const std::string& extension)
{
    CodecInfo codec_info;

    if (extension == ".mov")
    {
        codec_info.name = "Apple ProRes 422";
        codec_info.fourcc = "ap4h";
        codec_info.hardware_accelerated = true;
        codec_info.supports_encoding = true;
        codec_info.supports_decoding = true;
        codec_info.supported_extensions = {".mov"};
        return codec_info;
    }
    else if (extension == ".mp4")
    {
        codec_info.name = "H.264";
        codec_info.fourcc = "avc1";
        codec_info.hardware_accelerated = is_videotoolbox_available();
        codec_info.supports_encoding = true;
        codec_info.supports_decoding = true;
        codec_info.supported_extensions = {".mp4", ".m4v"};
        return codec_info;
    }

    return std::nullopt;
}

std::string VideoFormatSupport::opencv_fourcc_to_avfoundation(int opencv_fourcc)
{
    // Convert OpenCV fourcc integer to string
    std::string fourcc_str(4, '\0');
    fourcc_str[0] = (opencv_fourcc & 0xFF);
    fourcc_str[1] = ((opencv_fourcc >> 8) & 0xFF);
    fourcc_str[2] = ((opencv_fourcc >> 16) & 0xFF);
    fourcc_str[3] = ((opencv_fourcc >> 24) & 0xFF);

    // Map common OpenCV fourcc codes to AVFoundation codec identifiers
    static const std::unordered_map<std::string, std::string> fourcc_map = {
        {"H264", "avc1"},
        {"avc1", "avc1"},
        {"MJPG", "jpeg"},
        {"mp4v", "mp4v"},
        {"XVID", "xvid"}
    };

    auto it = fourcc_map.find(fourcc_str);
    return (it != fourcc_map.end()) ? it->second : fourcc_str;
}

int VideoFormatSupport::avfoundation_codec_to_opencv_fourcc(const std::string& av_codec)
{
    // Map AVFoundation codec identifiers to OpenCV fourcc codes
    static const std::unordered_map<std::string, int> codec_map = {
        {"avc1", cv::VideoWriter::fourcc('H','2','6','4')},
        {"hvc1", cv::VideoWriter::fourcc('H','2','6','5')},
        {"jpeg", cv::VideoWriter::fourcc('M','J','P','G')},
        {"mp4v", cv::VideoWriter::fourcc('m','p','4','v')}
    };

    auto it = codec_map.find(av_codec);
    return (it != codec_map.end()) ? it->second : -1;
}

bool VideoFormatSupport::is_videotoolbox_available()
{
    return VTIsHardwareDecodeSupported(kCMVideoCodecType_H264) || 
           VTIsHardwareDecodeSupported(kCMVideoCodecType_HEVC);
}

std::vector<VideoFormatSupport::CodecInfo> VideoFormatSupport::get_videotoolbox_codecs()
{
    if (!m_initialized)
        initialize();

    return m_videotoolbox_codecs;
}

void VideoFormatSupport::initialize_supported_formats()
{
    m_supported_formats.clear();

    // Add common macOS video formats
    FormatInfo mov_format;
    mov_format.container_format = "QuickTime Movie";
    mov_format.extensions = {".mov", ".qt"};
    mov_format.hardware_accelerated = true;
    m_supported_formats.push_back(mov_format);

    FormatInfo mp4_format;
    mp4_format.container_format = "MPEG-4";
    mp4_format.extensions = {".mp4", ".m4v"};
    mp4_format.hardware_accelerated = true;
    m_supported_formats.push_back(mp4_format);

    FormatInfo avi_format;
    avi_format.container_format = "AVI";
    avi_format.extensions = {".avi"};
    avi_format.hardware_accelerated = false;
    m_supported_formats.push_back(avi_format);
}

void VideoFormatSupport::initialize_videotoolbox_codecs()
{
    m_videotoolbox_codecs.clear();

    // Check H.264 support
    if (VTIsHardwareDecodeSupported(kCMVideoCodecType_H264))
    {
        CodecInfo h264_codec;
        h264_codec.name = "H.264 (Hardware)";
        h264_codec.fourcc = "avc1";
        h264_codec.hardware_accelerated = true;
        h264_codec.supports_encoding = true;
        h264_codec.supports_decoding = true;
        h264_codec.supported_extensions = {".mp4", ".m4v", ".mov"};
        m_videotoolbox_codecs.push_back(h264_codec);
    }

    // Check H.265/HEVC support
    if (VTIsHardwareDecodeSupported(kCMVideoCodecType_HEVC))
    {
        CodecInfo hevc_codec;
        hevc_codec.name = "H.265/HEVC (Hardware)";
        hevc_codec.fourcc = "hvc1";
        hevc_codec.hardware_accelerated = true;
        hevc_codec.supports_encoding = true;
        hevc_codec.supports_decoding = true;
        hevc_codec.supported_extensions = {".mp4", ".m4v", ".mov"};
        m_videotoolbox_codecs.push_back(hevc_codec);
    }
}

void VideoFormatSupport::query_avfoundation_capabilities()
{
    @autoreleasepool {
        // Query available export presets
        NSArray<NSString*>* export_presets = [AVAssetExportSession allExportPresets];
        
        // Update format information based on available presets
        for (auto& format : m_supported_formats)
        {
            for (NSString* preset in export_presets)
            {
                if ([preset containsString:@"H264"] || [preset containsString:@"HEVC"])
                {
                    format.hardware_accelerated = true;
                }
            }
        }
    }
}

//---------------------------------------------------------------------------------------------------------------------
// PathProcessor Implementation
//---------------------------------------------------------------------------------------------------------------------

std::string PathProcessor::normalize_path(const std::filesystem::path& path)
{
    @autoreleasepool {
        NSString* path_string = [NSString stringWithUTF8String:path.c_str()];
        NSString* normalized = [path_string stringByStandardizingPath];
        return std::string([normalized UTF8String]);
    }
}

bool PathProcessor::validate_video_path(const std::filesystem::path& path)
{
    // Check if path exists and is accessible
    if (!std::filesystem::exists(path))
        return false;

    // Check file extension for video formats
    std::string extension = path.extension().string();
    std::transform(extension.begin(), extension.end(), extension.begin(), ::tolower);
    
    static const std::vector<std::string> video_extensions = {
        ".mov", ".mp4", ".m4v", ".avi", ".mkv", ".webm", ".flv", ".wmv"
    };

    return std::find(video_extensions.begin(), video_extensions.end(), extension) != video_extensions.end();
}

std::string PathProcessor::normalize_unicode_filename(const std::string& filename)
{
    @autoreleasepool {
        NSString* filename_string = [NSString stringWithUTF8String:filename.c_str()];
        NSString* normalized = [filename_string precomposedStringWithCanonicalMapping];
        return std::string([normalized UTF8String]);
    }
}

bool PathProcessor::is_macos_filesystem_path(const std::filesystem::path& path)
{
    std::string path_str = path.string();
    
    // Check for macOS-specific path characteristics
    return path_str.find("/Users/") == 0 || 
           path_str.find("/Applications/") == 0 ||
           path_str.find("/System/") == 0 ||
           path_str.find("/Library/") == 0 ||
           path_str.find("/Volumes/") == 0;
}

std::string PathProcessor::convert_path_separators(const std::string& path)
{
    std::string converted = path;
    std::replace(converted.begin(), converted.end(), '\\', '/');
    return converted;
}

std::filesystem::path PathProcessor::resolve_path_aliases(const std::filesystem::path& path)
{
    @autoreleasepool {
        NSString* path_string = [NSString stringWithUTF8String:path.c_str()];
        NSString* resolved = [path_string stringByResolvingSymlinksInPath];
        return std::filesystem::path([resolved UTF8String]);
    }
}

bool PathProcessor::check_path_permissions(const std::filesystem::path& path, bool require_write)
{
    @autoreleasepool {
        NSString* path_string = [NSString stringWithUTF8String:path.c_str()];
        NSFileManager* file_manager = [NSFileManager defaultManager];
        
        if (require_write)
        {
            return [file_manager isWritableFileAtPath:path_string];
        }
        else
        {
            return [file_manager isReadableFileAtPath:path_string];
        }
    }
}

//---------------------------------------------------------------------------------------------------------------------
// ParallelProcessing Implementation
//---------------------------------------------------------------------------------------------------------------------

bool ParallelProcessing::m_initialized = false;
std::atomic<bool> ParallelProcessing::m_cancellation_requested{false};
size_t ParallelProcessing::m_optimal_queue_count = 0;

bool ParallelProcessing::initialize()
{
    if (m_initialized)
        return true;

    // Determine optimal queue count based on system capabilities
    m_optimal_queue_count = std::max(1u, std::thread::hardware_concurrency());
    
    // On macOS, we typically want to leave some cores for the system
    if (m_optimal_queue_count > 2)
    {
        m_optimal_queue_count = m_optimal_queue_count - 1;
    }

    m_cancellation_requested = false;
    m_initialized = true;
    return true;
}

void ParallelProcessing::release()
{
    if (m_initialized)
    {
        m_cancellation_requested = false;
        m_initialized = false;
    }
}

size_t ParallelProcessing::get_optimal_queue_count()
{
    if (!m_initialized)
        initialize();
    
    return m_optimal_queue_count;
}

bool ParallelProcessing::is_cancelled()
{
    return m_cancellation_requested.load();
}

void ParallelProcessing::request_cancellation()
{
    m_cancellation_requested = true;
}

void ParallelProcessing::reset_cancellation()
{
    m_cancellation_requested = false;
}

//---------------------------------------------------------------------------------------------------------------------
// HardwareAcceleration Implementation
//---------------------------------------------------------------------------------------------------------------------

bool HardwareAcceleration::is_metal_available()
{
    // Check if Metal framework is available (macOS 10.11+)
    return true; // Assume available on supported macOS versions
}

bool HardwareAcceleration::is_videotoolbox_encoding_available()
{
    return VTIsHardwareDecodeSupported(kCMVideoCodecType_H264);
}

bool HardwareAcceleration::is_videotoolbox_decoding_available()
{
    return VTIsHardwareDecodeSupported(kCMVideoCodecType_H264) || 
           VTIsHardwareDecodeSupported(kCMVideoCodecType_HEVC);
}

std::vector<int> HardwareAcceleration::get_hardware_acceleration_properties(int width, int height, int codec_fourcc)
{
    std::vector<int> properties;

    // Enable hardware acceleration if available
    if (is_videotoolbox_decoding_available())
    {
        properties.push_back(cv::CAP_PROP_HW_ACCELERATION);
        properties.push_back(cv::VIDEO_ACCELERATION_ANY);
        
        properties.push_back(cv::CAP_PROP_HW_ACCELERATION_USE_OPENCL);
        properties.push_back(1);
    }

    // Set optimal buffer size for hardware processing
    properties.push_back(cv::CAP_PROP_BUFFERSIZE);
    properties.push_back(3); // Triple buffering for smooth playback

    return properties;
}

bool HardwareAcceleration::enable_hardware_decoding(cv::VideoCapture& capture)
{
    if (!is_videotoolbox_decoding_available())
        return false;

    // Set hardware acceleration properties
    bool success = true;
    success &= capture.set(cv::CAP_PROP_HW_ACCELERATION, cv::VIDEO_ACCELERATION_ANY);
    success &= capture.set(cv::CAP_PROP_HW_ACCELERATION_USE_OPENCL, 1);
    
    return success;
}

bool HardwareAcceleration::enable_hardware_encoding(cv::VideoWriter& writer)
{
    if (!is_videotoolbox_encoding_available())
        return false;

    // Hardware encoding properties are typically set during VideoWriter construction
    // This function serves as a validation check
    return true;
}

} // namespace clt::macos

#endif // MACOS_BUILD