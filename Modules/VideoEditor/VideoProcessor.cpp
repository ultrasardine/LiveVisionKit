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

#include "VideoProcessor.hpp"

#include <type_traits>
#include <utility>

namespace clt
{
//---------------------------------------------------------------------------------------------------------------------

    constexpr size_t FILTER_TIMING_SAMPLES = 300;
    constexpr const char* RENDER_WINDOW_NAME = "LVK Output";

//---------------------------------------------------------------------------------------------------------------------

    VideoProcessor::VideoProcessor(VideoIOConfiguration configuration)
        : m_Configuration(std::move(configuration))
    {
#ifdef MACOS_BUILD
        setup_macos_parallel_processing();
#endif
    }

//---------------------------------------------------------------------------------------------------------------------

    VideoProcessor::~VideoProcessor()
    {
#ifdef MACOS_BUILD
        cleanup_macos_parallel_processing();
#endif
    }

//---------------------------------------------------------------------------------------------------------------------

    std::optional<std::string> VideoProcessor::initialize_configuration()
    {
#ifdef MACOS_BUILD
        // Initialize macOS video support
        if(auto error = initialize_macos_video_support(); error.has_value())
            return error;
#endif

        // Open input stream
        std::optional<std::string> input_error;
        std::visit([&, this](auto&& source){
            using source_type = std::decay_t<decltype(source)>;

            if constexpr(std::is_same_v<source_type, std::filesystem::path>)
            {
#ifdef MACOS_BUILD
                // Use macOS-specific input configuration
                input_error = configure_macos_input_stream();
#else
                std::vector<int> properties = {
                    cv::CAP_PROP_HW_ACCELERATION, 1,
                    cv::CAP_PROP_HW_ACCELERATION_USE_OPENCL, 1
                };

                m_DeviceCapture = false;
                m_InputStream = cv::VideoCapture(source.string(), cv::CAP_FFMPEG, properties);
                if(!m_InputStream.isOpened())
                    input_error = cv::format("Failed to open the input video \'%s\'", source.string().c_str());
#endif
            }
            else if constexpr(std::is_same_v<source_type, uint32_t>)
            {
                m_DeviceCapture = true;
                m_InputStream = cv::VideoCapture(source);
                if(!m_InputStream.isOpened())
                    input_error = cv::format("Failed to capture device \'%u\'", source);
            }
            else input_error = "No input source was specified!";
        },
        m_Configuration.input_source);

        if(input_error.has_value())
            return input_error;

        // Configure the filter
        m_Processor.reconfigure([&](lvk::CompositeFilterSettings& settings){
            for(auto& filter : m_Configuration.filter_chain)
            {
                filter->set_timing_samples(FILTER_TIMING_SAMPLES);
                settings.filter_chain.push_back(filter);
            }
        });

        // Load data logger
        if(m_Configuration.log_target.has_value())
        {
            m_DataLogStream.open(*m_Configuration.log_target);
            if(!m_DataLogStream.good())
                return "Failed to open data logging stream";

            m_DataLogger.emplace(m_DataLogStream);
        }

        return std::nullopt;
    }

//---------------------------------------------------------------------------------------------------------------------

    std::optional<std::string> VideoProcessor::initialize_output_stream(const cv::Size frame_size)
    {
        if(!m_Configuration.output_target.has_value())
            return "Could not create output stream, no target was specified";

#ifdef MACOS_BUILD
        // Use macOS-specific output configuration
        return configure_macos_output_stream(frame_size);
#else
        try {
            std::vector<int> properties = {
                cv::VideoWriterProperties::VIDEOWRITER_PROP_HW_ACCELERATION, 1,
                cv::VideoWriterProperties::VIDEOWRITER_PROP_HW_ACCELERATION_USE_OPENCL, 1
            };

            m_OutputStream = cv::VideoWriter(
                m_Configuration.output_target->string(),
                cv::CAP_FFMPEG,
                m_Configuration.output_codec.value_or(
                    static_cast<int>(m_InputStream.get(cv::CAP_PROP_FOURCC))
                ),
                m_Configuration.output_framerate.value_or(
                    std::max(m_InputStream.get(cv::CAP_PROP_FPS), 1.0)
                ),
                frame_size,
                properties
            );
        }
        catch(std::exception& e)
        {
            return cv::format(
                "Failed to create output stream with error \'%s\'",
                e.what()
            );
        }

        // If stream is still not opened, then creation failed
        if(!m_OutputStream.isOpened())
        {
            return cv::format(
                "Failed to create an output stream at \'%s\'",
                m_Configuration.output_target->string().c_str()
            );
        }

        return std::nullopt;
#endif
    }

//---------------------------------------------------------------------------------------------------------------------

    void VideoProcessor::stop()
    {
        m_Terminate = true;
    }

//---------------------------------------------------------------------------------------------------------------------

    std::optional<std::string> VideoProcessor::run()
    {
        std::optional<std::string> runtime_error;

        runtime_error = initialize_configuration();
        if(runtime_error.has_value())
            return runtime_error;

        // Create output window, making sure its resizable
        if(m_Configuration.render_output)
            cv::namedWindow(RENDER_WINDOW_NAME, cv::WINDOW_NORMAL | cv::WINDOW_KEEPRATIO);

        m_FrameTimer.start();
        m_ProcessTimer.start();
        lvk::Time last_update_time;

        // Run the processor filter
        m_Terminate = false;
        m_Processor.stream(
            m_InputStream,
            [&, this](lvk::Frame& frame) {
                // Write output
                if(m_Configuration.output_target.has_value())
                {
                    // Lazily initialize the output stream on first output frame
                    if(!m_OutputStream.isOpened())
                    {
                        runtime_error = initialize_output_stream(frame.size());
                        if(runtime_error.has_value())
                            return true;
                    }

                    m_OutputStream.write(frame);
                }

                // Display output
                if(m_Configuration.render_output)
                {
                    cv::imshow(RENDER_WINDOW_NAME, frame);

                    // Close display if escape is pressed, also note that
                    // the poll event is required to update the window.
                    if(const auto key = cv::pollKey(); key == 27)
                    {
                        m_Configuration.render_output = false;
                        cv::destroyAllWindows();

                        // If the input is a device capture or there is no output path, then
                        // we consider the display to the output. So closing the window should
                        // also terminate the processing. This is so that we can decide when to
                        // end indefinite device capture streams, and to avoid accidentally
                        // leaving the processor running in the background indefinitely.
                        return m_DeviceCapture || !m_Configuration.output_target.has_value();
                    }
                }

                // Update the frame timer
                if(m_Configuration.render_output && m_Configuration.render_period.has_value())
                {
                    // If we are displaying the output at a fixed frequency,
                    // then we need to wait to match the user's timestep here.
                    m_FrameTimer.tick(*m_Configuration.render_period);
                }
                else m_FrameTimer.tick();

                // Run all update procedures (logging etc.)
                const auto elapsed_time = m_ProcessTimer.elapsed();
                if(last_update_time.is_zero() || elapsed_time > last_update_time + m_Configuration.update_period)
                {
                    last_update_time = elapsed_time;
                    write_to_loggers();
                }

                return m_Terminate;
            },
            m_Configuration.print_timings || m_DataLogger.has_value()
        );

        // Run loggers one last time to ensure we have the latest statistics displayed.
        write_to_loggers();

        return runtime_error;
    }

//---------------------------------------------------------------------------------------------------------------------

    void VideoProcessor::write_to_loggers()
    {
        m_ConsoleLogger.clear();

        print_progress();
        if(m_Configuration.print_timings)
            print_filter_timings();

        if(m_DataLogger.has_value())
            log_timing_data();
    }

//---------------------------------------------------------------------------------------------------------------------

    void VideoProcessor::print_progress()
    {
        // NOTE: The frame count is not valid for device capture streams
        double frame_count = m_InputStream.get(cv::CAP_PROP_FRAME_COUNT);
        double frame_number = m_InputStream.get(cv::CAP_PROP_POS_FRAMES);

        // Input Stream Info
        m_ConsoleLogger << "Processing target: ";
        if(!m_DeviceCapture)
        {
            m_ConsoleLogger << std::get<std::filesystem::path>(m_Configuration.input_source).string()
                            << "  " << make_progress_bar(40, frame_number / frame_count)
                            << ConsoleLogger::Next;
        }
        else m_ConsoleLogger << "Device Capture" << ConsoleLogger::Next;

        // Print Elapsed time
        m_ConsoleLogger << "   Elapsed: " << m_ProcessTimer.elapsed().hms();
        if(!m_DeviceCapture)
        {
            lvk::Time est_remaining_time = lvk::Time::Seconds(
                std::ceil((frame_count - frame_number) / m_FrameTimer.average().frequency())
            );
            m_ConsoleLogger << " (est. " << est_remaining_time.hms() << " remaining)";
        }
        m_ConsoleLogger << ConsoleLogger::Next;

        // Print current frame input
        // NOTE: CAP_PROP_POS_FRAMES may not be supported by the VideoCapture backend, leading
        // to an invalid frame number. If we suspect this is the case, switch over to using the
        // frame timers tick count, which counts all but any empty output frames.
        m_ConsoleLogger << "   Frame: "
                        << ((frame_number <= 0) ? m_FrameTimer.tick_count() : static_cast<uint64_t>(frame_number))
                        << ConsoleLogger::Next;

        // Print current FPS
        m_ConsoleLogger << "   FPS: "
                        << std::fixed << std::setprecision(0) << m_FrameTimer.average().frequency()
                        << ConsoleLogger::Next;
    }

//---------------------------------------------------------------------------------------------------------------------

    void VideoProcessor::print_filter_timings()
    {
        // Print timing data for each of the filters
        m_ConsoleLogger << std::setprecision(2);
        m_ConsoleLogger << ConsoleLogger::Next << "Filters: " << ConsoleLogger::Next;
        for(size_t i = 0; i < m_Processor.filter_count(); i++)
        {
            auto filter = m_Processor.filters(i);
            auto average_timing = filter->timings().average();

            m_ConsoleLogger << std::to_string(i) <<  ".   "
                            << filter->alias()
                            << "\t" << average_timing.milliseconds() << "ms"
                            << " +/- " << filter->timings().deviation().milliseconds() << "ms"
                            << "   (" << static_cast<uint64_t>(average_timing.frequency()) << "FPS)"
                            << ConsoleLogger::Next;
        }
    }

//---------------------------------------------------------------------------------------------------------------------

    void VideoProcessor::log_timing_data()
    {
        LVK_ASSERT(m_DataLogger.has_value());

        lvk::CSVLogger& logger = *m_DataLogger;

        // On first log, add all the headers as filter names
        if(!logger.has_started())
        {
            // Format is..
            // 1. Output Frame Number
            // 2. Processor frametime
            // 3. All filter frametimes
            // 4. Processor deviation
            // 5. All filter deviations

            logger << "Output Frame";

            logger << "Processor Frametime (ms)";
            for(auto& filter : m_Processor.filters())
                logger << (filter->alias() + " Frametime (ms)");

            // Then log all the frame deviation times
            logger << "Processor Deviation (ms)";
            for(auto& filter : m_Processor.filters())
                logger << (filter->alias() + " Deviation (ms)");

            logger.next();
        }

        // write frame number
        logger << m_FrameTimer.tick_count();

        // write all frametimes
        logger << m_FrameTimer.average().milliseconds();
        for(auto& filter : m_Processor.filters())
            logger << filter->timings().average().milliseconds();

        // write all frame deviation times
        logger << m_FrameTimer.deviation().milliseconds();
        for(auto& filter : m_Processor.filters())
            logger << filter->timings().deviation().milliseconds();

        logger.next();
    }

//---------------------------------------------------------------------------------------------------------------------

    std::string VideoProcessor::make_progress_bar(const uint32_t length, const double progress)
    {
        LVK_ASSERT_01(progress);

        const auto position = static_cast<uint32_t>(progress * static_cast<double>(length));

        std::string bar;
        bar.reserve(length + 10);

        bar.push_back('[');
        for(uint32_t i = 0; i < length; i++)
            bar.push_back(i < position ? '=' : ' ');
        bar += "| " + cv::format("%0.1f%%", 100.0 * progress) + ']';

        return bar;
    }

//---------------------------------------------------------------------------------------------------------------------

#ifdef MACOS_BUILD
    std::optional<std::string> VideoProcessor::initialize_macos_video_support()
    {
        if (!clt::macos::VideoFormatSupport::initialize())
        {
            return "Failed to initialize macOS video format support";
        }
        return std::nullopt;
    }

    std::optional<std::string> VideoProcessor::configure_macos_input_stream()
    {
        auto input_path = std::get<std::filesystem::path>(m_Configuration.input_source);
        
        // Normalize and validate the input path
        std::string normalized_path = clt::macos::PathProcessor::normalize_path(input_path);
        if (!clt::macos::PathProcessor::validate_video_path(normalized_path))
        {
            return cv::format("Invalid video file path: \'%s\'", normalized_path.c_str());
        }

        // Check path permissions
        if (!clt::macos::PathProcessor::check_path_permissions(normalized_path, false))
        {
            return cv::format("Cannot read video file: \'%s\' (permission denied)", normalized_path.c_str());
        }

        // Detect video format and get optimal settings
        auto format_info = clt::macos::VideoFormatSupport::detect_format(normalized_path);
        if (!format_info.has_value())
        {
            return cv::format("Unsupported video format: \'%s\'", normalized_path.c_str());
        }

        // Get hardware acceleration properties
        std::vector<int> properties = clt::macos::HardwareAcceleration::get_hardware_acceleration_properties(
            1920, 1080, // Default resolution for property calculation
            cv::VideoWriter::fourcc('H','2','6','4') // Default codec
        );

        m_DeviceCapture = false;
        m_InputStream = cv::VideoCapture(normalized_path, cv::CAP_FFMPEG, properties);
        
        if (!m_InputStream.isOpened())
        {
            return cv::format("Failed to open video file: \'%s\'", normalized_path.c_str());
        }

        // Enable hardware decoding if available
        clt::macos::HardwareAcceleration::enable_hardware_decoding(m_InputStream);

        return std::nullopt;
    }

    std::optional<std::string> VideoProcessor::configure_macos_output_stream(const cv::Size frame_size)
    {
        auto output_path = *m_Configuration.output_target;
        
        // Normalize and validate the output path
        std::string normalized_path = clt::macos::PathProcessor::normalize_path(output_path);
        
        // Check if we can write to the output directory
        auto parent_path = std::filesystem::path(normalized_path).parent_path();
        if (!clt::macos::PathProcessor::check_path_permissions(parent_path, true))
        {
            return cv::format("Cannot write to directory: \'%s\' (permission denied)", parent_path.string().c_str());
        }

        // Get native codec recommendation for the output format
        std::string extension = output_path.extension().string();
        auto codec_recommendation = clt::macos::VideoFormatSupport::get_native_codec_recommendation(extension);
        
        int output_codec;
        if (codec_recommendation.has_value() && m_Configuration.output_codec.has_value())
        {
            // Use user-specified codec
            output_codec = *m_Configuration.output_codec;
        }
        else if (codec_recommendation.has_value())
        {
            // Use recommended native codec
            output_codec = clt::macos::VideoFormatSupport::avfoundation_codec_to_opencv_fourcc(codec_recommendation->fourcc);
            if (output_codec == -1)
            {
                // Fallback to input codec
                output_codec = static_cast<int>(m_InputStream.get(cv::CAP_PROP_FOURCC));
            }
        }
        else
        {
            // Fallback to input codec
            output_codec = static_cast<int>(m_InputStream.get(cv::CAP_PROP_FOURCC));
        }

        // Get hardware acceleration properties for encoding
        std::vector<int> properties = clt::macos::HardwareAcceleration::get_hardware_acceleration_properties(
            frame_size.width, frame_size.height, output_codec
        );

        try {
            m_OutputStream = cv::VideoWriter(
                normalized_path,
                cv::CAP_FFMPEG,
                output_codec,
                m_Configuration.output_framerate.value_or(
                    std::max(m_InputStream.get(cv::CAP_PROP_FPS), 1.0)
                ),
                frame_size,
                properties
            );
        }
        catch(std::exception& e)
        {
            return cv::format(
                "Failed to create output stream with error: \'%s\'",
                e.what()
            );
        }

        // If stream is still not opened, then creation failed
        if (!m_OutputStream.isOpened())
        {
            return cv::format(
                "Failed to create output stream at: \'%s\'",
                normalized_path.c_str()
            );
        }

        // Enable hardware encoding if available
        clt::macos::HardwareAcceleration::enable_hardware_encoding(m_OutputStream);

        return std::nullopt;
    }

    void VideoProcessor::setup_macos_parallel_processing()
    {
        clt::macos::ParallelProcessing::initialize();
    }

    void VideoProcessor::cleanup_macos_parallel_processing()
    {
        clt::macos::ParallelProcessing::release();
    }
#endif

//---------------------------------------------------------------------------------------------------------------------

}