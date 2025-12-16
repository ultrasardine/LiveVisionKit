
# Set up project 
project(lvk-core LANGUAGES CXX)
set(CMAKE_CXX_STANDARD 20)

# Set up library 
add_library(${PROJECT_NAME})
set_target_properties(${PROJECT_NAME} PROPERTIES DEBUG_POSTFIX ${LVK_DEBUG_POSTFIX})

set_property(TARGET ${PROJECT_NAME} PROPERTY POSITION_INDEPENDENT_CODE ON)
set_property(TARGET ${PROJECT_NAME} PROPERTY PROJECT_LABEL "LiveVisionKit")
set_property(TARGET ${PROJECT_NAME} PROPERTY INTERPROCEDURAL_OPTIMIZATION TRUE)
set_property(TARGET ${PROJECT_NAME} PROPERTY MSVC_RUNTIME_LIBRARY "MultiThreaded$<$<CONFIG:Debug>:Debug>")

# Disable assert checks
if(DISABLE_CHECKS)
    add_definitions(-DLVK_DISABLE_CHECKS)
    add_definitions(-DNDEBUG)
endif()

# Find all dependencies
set(THREADS_PREFER_PTHREAD_FLAG ON)
find_package(Threads REQUIRED)

set(EIGEN_BUILD_PATH "./Dependencies/eigen/build/" CACHE PATH "The path to the Eigen build folder")
find_package(Eigen3 REQUIRED NO_MODULE PATHS ${EIGEN_BUILD_PATH})

# Include all dependencies
target_include_directories(
    ${PROJECT_NAME} 
    PUBLIC 
        ${CMAKE_CURRENT_SOURCE_DIR} 
        ${OpenCV_INCLUDE_DIRS}
)    

# Link all dependencies
target_link_libraries(
    ${PROJECT_NAME} 
    Threads::Threads
    opencv_core
    opencv_video
    opencv_imgproc
    opencv_calib3d
    opencv_highgui
    opencv_features2d
    Eigen3::Eigen
)

if(UNIX AND NOT MACOS_BUILD)
# Required by opencv_highgui on Linux
target_link_libraries(
    ${PROJECT_NAME}
    Qt5::Core
    Qt5::Gui
    Qt5::Widgets
    Qt5::Test
    Qt5::Concurrent
    Qt5::OpenGL
)
elseif(MACOS_BUILD)
# Required by opencv_highgui and LVK on macOS
target_link_libraries(
    ${PROJECT_NAME}
    Qt5::Core
    Qt5::Gui
    Qt5::Widgets
    Qt5::Test
    Qt5::Concurrent
    Qt5::OpenGL
)

# Link macOS-specific frameworks
if(COREFOUNDATION_FRAMEWORK)
    target_link_libraries(${PROJECT_NAME} ${COREFOUNDATION_FRAMEWORK})
endif()
if(COREVIDEO_FRAMEWORK)
    target_link_libraries(${PROJECT_NAME} ${COREVIDEO_FRAMEWORK})
endif()
if(ACCELERATE_FRAMEWORK)
    target_link_libraries(${PROJECT_NAME} ${ACCELERATE_FRAMEWORK})
endif()
if(OPENCL_FRAMEWORK)
    target_link_libraries(${PROJECT_NAME} ${OPENCL_FRAMEWORK})
endif()
if(METAL_FRAMEWORK)
    target_link_libraries(${PROJECT_NAME} ${METAL_FRAMEWORK})
endif()
if(METALPERFORMANCESHADERS_FRAMEWORK)
    target_link_libraries(${PROJECT_NAME} ${METALPERFORMANCESHADERS_FRAMEWORK})
endif()
endif()


# Set up install rules
install(
    TARGETS ${PROJECT_NAME}
    DESTINATION ${LVK_BINARY_DIR}
)
install(
    DIRECTORY ${CMAKE_CURRENT_SOURCE_DIR}
    DESTINATION ${LVK_INCLUDES_DIR}
    FILES_MATCHING  
        PATTERN "*.hpp"
        PATTERN "*.tpp"
        PATTERN "*.h"
)

# Add library sources
target_sources(
    ${PROJECT_NAME}
    PRIVATE
        OpenVisionKit.hpp
        Directives.hpp
        Directives.cpp

        Functions/OpenCL/Kernels.hpp
        Functions/OpenCL/Kernels.cpp
        # Temporarily disable macOS-specific files for checkpoint
        # Functions/OpenCL/MacOSAcceleration.hpp
        # Functions/OpenCL/MacOSAcceleration.mm
        # Functions/OpenCL/CoreVideoIntegration.hpp
        # Functions/OpenCL/CoreVideoIntegration.mm
        Functions/Extensions.hpp
        Functions/Extensions.cpp
        Functions/Container.hpp
        Functions/Container.tpp
        Functions/Drawing.hpp
        Functions/Drawing.tpp
        Functions/Image.hpp
        Functions/Image.cpp
        Functions/Logic.hpp
        Functions/Logic.tpp
        Functions/Math.hpp
        Functions/Math.tpp
        Functions/Text.hpp
        Functions/Text.tpp

        Filters/CompositeFilter.cpp
        Filters/CompositeFilter.hpp
        Filters/ConversionFilter.cpp
        Filters/ConversionFilter.hpp
        Filters/DeblockingFilter.cpp
        Filters/DeblockingFilter.hpp
        Filters/StabilizationFilter.cpp
        Filters/StabilizationFilter.hpp
        Filters/ScalingFilter.cpp
        Filters/ScalingFilter.hpp
        Filters/VideoFilter.cpp
        Filters/VideoFilter.hpp

        Logging/CSVLogger.cpp
        Logging/CSVLogger.hpp
        Logging/Logger.hpp
        Logging/Logger.tpp

        Math/BoundingQuad.cpp
        Math/BoundingQuad.hpp
        Math/Homography.cpp
        Math/Homography.hpp
        Math/WarpMesh.hpp
        Math/WarpMesh.cpp
        Math/VirtualGrid.hpp
        Math/VirtualGrid.cpp

        Data/StreamBuffer.hpp
        Data/StreamBuffer.tpp
        Data/SpatialMap.hpp
        Data/SpatialMap.tpp
        Data/VideoFrame.cpp
        Data/VideoFrame.hpp
        Data/Iterators.hpp
        Data/Iterators.tpp

        Timing/Stopwatch.cpp
        Timing/Stopwatch.hpp
        Timing/TickTimer.cpp
        Timing/TickTimer.hpp
        Timing/Time.cpp
        Timing/Time.hpp

        Utility/Configurable.hpp
        Utility/Configurable.tpp
        Utility/Unique.hpp
        Utility/Unique.tpp

        Vision/CameraCalibrator.cpp
        Vision/CameraCalibrator.hpp
        Vision/FeatureDetector.cpp
        Vision/FeatureDetector.hpp
        Vision/FrameTracker.cpp
        Vision/FrameTracker.hpp
        Vision/PathSmoother.cpp
        Vision/PathSmoother.hpp
)

# Add macOS-specific privacy and security sources
if(MACOS_BUILD)
    # Enable Objective-C++ for macOS-specific files
    enable_language(OBJCXX)
    
    target_sources(${PROJECT_NAME} PRIVATE
        Utility/MacOSPrivacy.hpp
        Utility/MacOSPrivacy.mm
    )
    
    # Link AVFoundation for privacy permission handling
    find_library(AVFOUNDATION_FRAMEWORK AVFoundation)
    find_library(APPKIT_FRAMEWORK AppKit)
    
    if(AVFOUNDATION_FRAMEWORK)
        target_link_libraries(${PROJECT_NAME} ${AVFOUNDATION_FRAMEWORK})
    endif()
    
    if(APPKIT_FRAMEWORK)
        target_link_libraries(${PROJECT_NAME} ${APPKIT_FRAMEWORK})
    endif()
    
    # Install privacy manifest for App Store compliance
    install(
        FILES ${CMAKE_CURRENT_SOURCE_DIR}/PrivacyInfo.xcprivacy
        DESTINATION ${LVK_INCLUDES_DIR}/OpenVisionKit
    )
    
    # Configure macOS security features for core library
    if(COMMAND configure_macos_security)
        configure_macos_security(${PROJECT_NAME}
            ENABLE_HARDENED_RUNTIME
        )
    endif()
    
    if(COMMAND configure_sip_compatible_loading)
        configure_sip_compatible_loading(${PROJECT_NAME})
    endif()
    
    if(COMMAND add_security_compiler_flags)
        add_security_compiler_flags(${PROJECT_NAME})
    endif()
endif()
