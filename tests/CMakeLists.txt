# Test configuration for LiveVisionKit
cmake_minimum_required(VERSION 3.21)
project(lvk-tests CXX)

# Set up variables needed by the core library
set(LVK_DEBUG_POSTFIX "d")
set(DISABLE_CHECKS OFF)
set(LVK_BINARY_DIR "Binaries")
set(LVK_INCLUDES_DIR "Include")

# macOS Build Support
if(APPLE)
    set(MACOS_BUILD TRUE)
    add_definitions(-DMACOS_BUILD)
    
    # Find macOS frameworks
    find_library(COREFOUNDATION_FRAMEWORK CoreFoundation)
    find_library(COREVIDEO_FRAMEWORK CoreVideo)
    find_library(ACCELERATE_FRAMEWORK Accelerate)
    find_library(OPENCL_FRAMEWORK OpenCL)
endif()

# Find required packages
find_package(Catch2 3 QUIET)
find_package(OpenCV REQUIRED)
find_package(Eigen3 REQUIRED)

if(NOT Catch2_FOUND)
    # Download Catch2 if not found
    include(FetchContent)
    FetchContent_Declare(
        Catch2
        GIT_REPOSITORY https://github.com/catchorg/Catch2.git
        GIT_TAG v3.4.0
    )
    FetchContent_MakeAvailable(Catch2)
endif()

# Create test executable
add_executable(lvk-tests)
set_target_properties(lvk-tests PROPERTIES CXX_STANDARD 20)

# Link test dependencies
target_link_libraries(lvk-tests PRIVATE 
    Catch2::Catch2WithMain
    ${OpenCV_LIBS}
    Eigen3::Eigen
)

# Include directories
target_include_directories(lvk-tests PRIVATE 
    ${CMAKE_CURRENT_SOURCE_DIR}/../OpenVisionKit
    ${CMAKE_CURRENT_SOURCE_DIR}/../Modules/VideoEditor
    ${OpenCV_INCLUDE_DIRS}
)

# Include test sources
target_sources(lvk-tests PRIVATE
    test_macos_detection.cpp
    test_obs_plugin_integration.cpp
    test_binary_compatibility.cpp
    test_core_library_completeness.cpp
    test_execution_consistency.cpp
    test_cross_platform_validation.cpp
    test_cross_platform_result_consistency.cpp
    test_memory_leak_prevention.cpp
    test_security_configuration.cpp
)

# Add macOS-specific test sources
if(APPLE)
    target_sources(lvk-tests PRIVATE
        test_video_editor_macos.cpp
        test_macos_dependency_detection.cpp
        test_macos_path_handling.cpp
        test_macos_obs_plugin_loading.cpp
        ../Modules/VideoEditor/MacOSVideoSupport.mm
    )
    
    # Define MACOS_BUILD for macOS-specific code
    target_compile_definitions(lvk-tests PRIVATE MACOS_BUILD)
    
    # Link macOS frameworks for video editor tests
    find_library(AVFOUNDATION_FRAMEWORK AVFoundation)
    find_library(VIDEOTOOLBOX_FRAMEWORK VideoToolbox)
    find_library(COREFOUNDATION_FRAMEWORK CoreFoundation)
    find_library(FOUNDATION_FRAMEWORK Foundation)
    find_library(COREMEDIA_FRAMEWORK CoreMedia)
    
    if(AVFOUNDATION_FRAMEWORK)
        target_link_libraries(lvk-tests PRIVATE ${AVFOUNDATION_FRAMEWORK})
    endif()
    
    if(VIDEOTOOLBOX_FRAMEWORK)
        target_link_libraries(lvk-tests PRIVATE ${VIDEOTOOLBOX_FRAMEWORK})
    endif()
    
    if(COREFOUNDATION_FRAMEWORK)
        target_link_libraries(lvk-tests PRIVATE ${COREFOUNDATION_FRAMEWORK})
    endif()
    
    if(FOUNDATION_FRAMEWORK)
        target_link_libraries(lvk-tests PRIVATE ${FOUNDATION_FRAMEWORK})
    endif()
    
    if(COREMEDIA_FRAMEWORK)
        target_link_libraries(lvk-tests PRIVATE ${COREMEDIA_FRAMEWORK})
    endif()
endif()

# Add tests to CTest
include(CTest)
include(Catch)
catch_discover_tests(lvk-tests)

# Add custom test for macOS detection
add_test(
    NAME macos_detection_property_test
    COMMAND lvk-tests "[macos-detection]"
)

# Add custom test for setup script
add_test(
    NAME setup_script_property_test
    COMMAND lvk-tests "[setup-script]"
)

# Add custom test for path discovery
add_test(
    NAME path_discovery_property_test
    COMMAND lvk-tests "[path-discovery]"
)

# Add custom test for feature parity
add_test(
    NAME feature_parity_property_test
    COMMAND lvk-tests "[feature-parity]"
)

# Add custom test for binary compatibility
add_test(
    NAME binary_compatibility_property_test
    COMMAND lvk-tests "[binary-compatibility]"
)

# Add custom test for core library completeness
add_test(
    NAME core_library_completeness_property_test
    COMMAND lvk-tests "[core-library-completeness]"
)

# Add custom test for OBS plugin integration
add_test(
    NAME obs_plugin_integration_property_test
    COMMAND lvk-tests "[obs-plugin-integration]"
)

# Add macOS-specific tests
if(APPLE)
    add_test(
        NAME video_format_handling_property_test
        COMMAND lvk-tests "[video][macos][property]"
    )
    
    add_test(
        NAME path_processing_property_test
        COMMAND lvk-tests "[path][macos][property]"
    )
    
    add_test(
        NAME memory_leak_prevention_property_test
        COMMAND lvk-tests "[memory-leak-prevention]"
    )
    
    add_test(
        NAME security_configuration_property_test
        COMMAND lvk-tests "[security-configuration]"
    )
endif()