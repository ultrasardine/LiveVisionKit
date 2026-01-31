cmake_minimum_required(VERSION 3.21)

# macOS Build Support
if(APPLE)
    set(MACOS_BUILD TRUE)
    message(STATUS "Configuring for macOS build...")
    
    # Set macOS-specific variables
    set(CMAKE_OSX_DEPLOYMENT_TARGET "10.15" CACHE STRING "Minimum macOS version")
    
    # Enable macOS-specific compiler flags
    set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -stdlib=libc++")
    
    # Add macOS-specific definitions
    add_definitions(-DMACOS_BUILD)
    
    # Configure for both Intel and Apple Silicon if not specified
    if(NOT CMAKE_OSX_ARCHITECTURES)
        set(CMAKE_OSX_ARCHITECTURES "x86_64;arm64" CACHE STRING "Build architectures for macOS")
    endif()
    
    message(STATUS "${MI}macOS Deployment Target: ${CMAKE_OSX_DEPLOYMENT_TARGET}")
    message(STATUS "${MI}macOS Architectures: ${CMAKE_OSX_ARCHITECTURES}")
else()
    set(MACOS_BUILD FALSE)
endif()

set(MI "   ") # Message indents
set_property(GLOBAL PROPERTY USE_FOLDERS ON)
set_property(GLOBAL PROPERTY PREDEFINED_TARGETS_FOLDER "CMakeTargets")


# Set up project 
if(APPLE)
    project(OpenVisionKit LANGUAGES C CXX OBJC OBJCXX)
else()
    project(OpenVisionKit LANGUAGES C CXX)
endif()
message(STATUS "\nConfiguring OpenVisionKit...")

# Project defines
set(LVK_CORE_DIR "${CMAKE_CURRENT_SOURCE_DIR}/OpenVisionKit/")
set(LVK_RELEASES_DIR "Releases")
set(LVK_INCLUDES_DIR "Include")
set(LVK_BINARY_DIR "Binaries")
set(LVK_DEBUG_POSTFIX "d")

# Set default install location
if(CMAKE_INSTALL_PREFIX_INITIALIZED_TO_DEFAULT)
    set(
        CMAKE_INSTALL_PREFIX
        "${CMAKE_BINARY_DIR}/Install/"
        CACHE PATH
        "The location to which build files will be installed" 
        FORCE
    )
endif(CMAKE_INSTALL_PREFIX_INITIALIZED_TO_DEFAULT)

# Project settings
set(BUILD_OBS_PLUGIN "ON" CACHE BOOL "Build the OBS-Studio plugin")
set(BUILD_VIDEO_EDITOR "ON" CACHE BOOL "Build the video editor CLT")
set(DISABLE_CHECKS "OFF" CACHE BOOL "Compile without asserts and pre-condition checks")
set(OPENCV_BUILD_PATH "./Dependencies/opencv/build/" CACHE PATH "The path to the OpenCV build folder")

# macOS-specific build settings
if(MACOS_BUILD)
    # Enable security features
    set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -fstack-protector-strong")
    
    # Performance optimizations for macOS
    if(CMAKE_BUILD_TYPE STREQUAL "Release")
        set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -O3 -DNDEBUG")
        # Enable Link Time Optimization for Release builds
        set(CMAKE_INTERPROCEDURAL_OPTIMIZATION TRUE)
    endif()
    
    # Debug settings
    if(CMAKE_BUILD_TYPE STREQUAL "Debug")
        set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -g -O0")
        # Enable AddressSanitizer for debug builds on macOS
        option(ENABLE_ASAN "Enable AddressSanitizer" OFF)
        if(ENABLE_ASAN)
            set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -fsanitize=address -fno-omit-frame-pointer")
            set(CMAKE_EXE_LINKER_FLAGS "${CMAKE_EXE_LINKER_FLAGS} -fsanitize=address")
        endif()
    endif()
    
    # Add macOS frameworks that might be needed
    find_library(COREFOUNDATION_FRAMEWORK CoreFoundation)
    find_library(COREVIDEO_FRAMEWORK CoreVideo)
    find_library(ACCELERATE_FRAMEWORK Accelerate)
    find_library(OPENCL_FRAMEWORK OpenCL)
    find_library(METAL_FRAMEWORK Metal)
    find_library(METALPERFORMANCESHADERS_FRAMEWORK MetalPerformanceShaders)
    
    if(COREFOUNDATION_FRAMEWORK)
        message(STATUS "${MI}Found CoreFoundation framework")
    endif()
    if(COREVIDEO_FRAMEWORK)
        message(STATUS "${MI}Found CoreVideo framework")
    endif()
    if(ACCELERATE_FRAMEWORK)
        message(STATUS "${MI}Found Accelerate framework")
    endif()
    if(OPENCL_FRAMEWORK)
        message(STATUS "${MI}Found OpenCL framework")
        set(MACOS_OPENCL_AVAILABLE TRUE)
        add_definitions(-DMACOS_OPENCL_AVAILABLE)
    else()
        message(WARNING "${MI}OpenCL framework not found - GPU acceleration will be disabled")
        set(MACOS_OPENCL_AVAILABLE FALSE)
    endif()
    # Temporarily disable Metal support to avoid Objective-C compilation issues
    # if(METAL_FRAMEWORK)
    #     message(STATUS "${MI}Found Metal framework")
    #     set(MACOS_METAL_AVAILABLE TRUE)
    #     add_definitions(-DMACOS_METAL_AVAILABLE)
    # endif()
    # if(METALPERFORMANCESHADERS_FRAMEWORK)
    #     message(STATUS "${MI}Found MetalPerformanceShaders framework")
    #     set(MACOS_MPS_AVAILABLE TRUE)
    #     add_definitions(-DMACOS_MPS_AVAILABLE)
    # endif()
endif()

# Load macOS dependency detection module
if(MACOS_BUILD)
    list(APPEND CMAKE_MODULE_PATH "${CMAKE_CURRENT_SOURCE_DIR}/cmake")
    include(FindMacOSDependencies)
    
    # Load macOS security configuration module
    include(MacOSSecurity)
    
    # Load macOS sandboxing configuration module (for App Store distribution)
    include(MacOSSandboxing)
    
    # Detect all macOS dependencies
    detect_macos_dependencies()
    
    # Check for missing dependencies and generate comprehensive error report
    set(MISSING_DEPENDENCIES "")
    set(INVALID_DEPENDENCIES "")
    
    if(NOT OPENCV_FOUND)
        list(APPEND MISSING_DEPENDENCIES "OpenCV")
    # Skip OpenCV validation - let find_package handle it
    # elseif(NOT OPENCV_VALID)
    #     list(APPEND INVALID_DEPENDENCIES "OpenCV")
    endif()
    
    if(NOT QT5_FOUND)
        list(APPEND MISSING_DEPENDENCIES "Qt5")
    # Skip Qt5 validation - let find_package handle it
    # elseif(NOT QT5_VALID)
    #     list(APPEND INVALID_DEPENDENCIES "Qt5")
    endif()
    
    if(NOT EIGEN3_FOUND)
        list(APPEND MISSING_DEPENDENCIES "Eigen3")
    elseif(NOT EIGEN3_VALID)
        list(APPEND INVALID_DEPENDENCIES "Eigen3")
    endif()
    
    # Generate diagnostic report if there are issues
    if(MISSING_DEPENDENCIES OR INVALID_DEPENDENCIES)
        generate_dependency_diagnostic()
        generate_complete_install_script()
        
        if(MISSING_DEPENDENCIES)
            string(REPLACE ";" ", " MISSING_LIST "${MISSING_DEPENDENCIES}")
            message(FATAL_ERROR "Required dependencies not found: ${MISSING_LIST}. Please install them using the methods shown above.")
        endif()
        
        if(INVALID_DEPENDENCIES)
            string(REPLACE ";" ", " INVALID_LIST "${INVALID_DEPENDENCIES}")
            message(FATAL_ERROR "Invalid dependency installations: ${INVALID_LIST}. Please reinstall them using the methods shown above.")
        endif()
    endif()
    
    # Report successful detection and call find_package
    message(STATUS "${MI}OpenCV Detection Method: ${OPENCV_DETECTION_METHOD}")
    message(STATUS "${MI}OpenCV Install Path: ${OPENCV_INSTALL_PATH}")
    
    # Set CMAKE_PREFIX_PATH to help find_package locate OpenCV
    list(APPEND CMAKE_PREFIX_PATH "${OPENCV_INSTALL_PATH}")
    find_package(OpenCV REQUIRED)
else()
    # Non-macOS OpenCV detection
    # First try system installation
    find_package(OpenCV QUIET)
    
    if(NOT OpenCV_FOUND AND OPENCV_BUILD_PATH AND EXISTS "${OPENCV_BUILD_PATH}")
        # Fall back to custom build path if system installation not found
        find_package(OpenCV REQUIRED PATHS ${OPENCV_BUILD_PATH} NO_DEFAULT_PATH)
    elseif(NOT OpenCV_FOUND)
        # If neither system nor custom path works, try without path restrictions
        find_package(OpenCV REQUIRED)
    endif()
endif()

if(OpenCV_FOUND)
    message(STATUS "${MI}Found OpenCV: YES")
    message(STATUS "${MI}OpenCV Version: ${OpenCV_VERSION}")
    message(STATUS "${MI}OpenCV Modules: ${OpenCV_LIBS}")
else()
    message(FATAL_ERROR "Failed to find OpenCV!")
endif()

# Platform-specific Qt5 detection
# Qt5 is ONLY required for VideoEditor (uses opencv_highgui which depends on Qt5)
# The OBS plugin must NOT link Qt5 as it conflicts with OBS's Qt6
if(BUILD_VIDEO_EDITOR)
    if(UNIX AND NOT MACOS_BUILD)
        # Linux-specific Qt5 detection
        find_package(Qt5 REQUIRED Core Gui Widgets Test Concurrent OpenGL)
    elseif(MACOS_BUILD)
        # macOS Qt5 detection - call find_package after detection
        if(QT5_FOUND)
            # Set CMAKE_PREFIX_PATH to help find_package locate Qt5
            list(APPEND CMAKE_PREFIX_PATH "${QT5_INSTALL_PATH}")
            find_package(Qt5 REQUIRED COMPONENTS Core Gui Widgets Test Concurrent OpenGL)
        else()
            generate_qt5_install_suggestions()
            message(FATAL_ERROR "Qt5 is required for VideoEditor but was not found. Please install Qt5 using one of the methods above, or disable VideoEditor with -DBUILD_VIDEO_EDITOR=OFF")
        endif()
        
        message(STATUS "${MI}Qt5 Detection Method: ${QT5_DETECTION_METHOD}")
        message(STATUS "${MI}Qt5 Install Path: ${QT5_INSTALL_PATH}")
        message(STATUS "${MI}Qt5 Version: ${Qt5_VERSION}")
    endif()
else()
    message(STATUS "${MI}Qt5: Skipped (VideoEditor not being built)")
endif()

# Eigen3 detection for macOS
if(MACOS_BUILD)
    if(NOT EIGEN3_FOUND)
        generate_eigen3_install_suggestions()
        message(FATAL_ERROR "Eigen3 is required but was not found. Please install Eigen3 using one of the methods above.")
    endif()
    
    if(NOT EIGEN3_VALID)
        message(FATAL_ERROR "Eigen3 installation is incomplete or invalid. Please reinstall Eigen3.")
    endif()
    
    message(STATUS "${MI}Eigen3 Detection Method: ${EIGEN3_DETECTION_METHOD}")
    message(STATUS "${MI}Eigen3 Install Path: ${EIGEN3_INSTALL_PATH}")
    if(Eigen3_VERSION)
        message(STATUS "${MI}Eigen3 Version: ${Eigen3_VERSION}")
    endif()
    
    # Try to use find_package first, then create target if needed
    find_package(Eigen3 QUIET)
    if(NOT TARGET Eigen3::Eigen)
        add_library(Eigen3::Eigen INTERFACE IMPORTED)
        set_target_properties(Eigen3::Eigen PROPERTIES
            INTERFACE_INCLUDE_DIRECTORIES "${Eigen3_INCLUDE_DIRS}"
        )
    endif()
endif()

# Enable testing if requested
option(ENABLE_TESTING "Enable testing" OFF)
if(ENABLE_TESTING)
    enable_testing()
    add_subdirectory(tests)
    message(STATUS "${MI}Testing enabled")
endif()

# Load sub-modules
add_subdirectory(OpenVisionKit)

if(BUILD_VIDEO_EDITOR)                                 
    message(STATUS "\nBuilding with video editor CLT...")
    add_subdirectory(Modules/VideoEditor)
endif()

if(BUILD_OBS_PLUGIN)
    message(STATUS "\nBuilding with LVK OBS-Studio plugin...")
    add_subdirectory(Modules/OBS-Plugin)
endif()

message(STATUS "\n")
