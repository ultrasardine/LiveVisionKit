
# Set up project 
project(lvk-editor CXX)
set(CMAKE_CXX_STANDARD 20)

# Set up executable 
add_executable(${PROJECT_NAME})
set_target_properties(${PROJECT_NAME} PROPERTIES DEBUG_POSTFIX ${LVK_DEBUG_POSTFIX})

set_property(TARGET ${PROJECT_NAME} PROPERTY PROJECT_LABEL "Video Editor")
set_property(TARGET ${PROJECT_NAME} PROPERTY INTERPROCEDURAL_OPTIMIZATION TRUE)
set_property(TARGET ${PROJECT_NAME} PROPERTY MSVC_RUNTIME_LIBRARY "MultiThreaded$<$<CONFIG:Debug>:Debug>")

# Disable assert checks
if(DISABLE_CHECKS)
    add_definitions(-DLVK_DISABLE_CHECKS)
    add_definitions(-DNDEBUG)
endif()

# Project settings
message(STATUS "${MI}No Configuration Options.")

# Include all dependencies
target_include_directories(
    ${PROJECT_NAME}
    PRIVATE
        ${CMAKE_CURRENT_SOURCE_DIR} 
        ${OpenCV_INCLUDE_DIRS}
        ${LVK_CORE_DIR}
)

# Link all dependencies
add_dependencies(${PROJECT_NAME} lvk-core)
target_link_libraries(
    ${PROJECT_NAME}
    lvk-core
    opencv_videoio
)


# Set up install rules
install(
    TARGETS ${PROJECT_NAME}
    DESTINATION ${LVK_RELEASES_DIR}
)

# Add executable sources
target_sources(
    ${PROJECT_NAME}
    PRIVATE
        Application.cpp
        VideoProcessor.hpp
        VideoProcessor.cpp
        VideoIOConfiguration.cpp
        VideoIOConfiguration.hpp
        ConsoleLogger.hpp
        ConsoleLogger.cpp
        OptionParser.hpp
        OptionParser.tpp
        FilterParser.hpp
        FilterParser.tpp
)

# Add macOS-specific sources
if(APPLE)
    target_sources(
        ${PROJECT_NAME}
        PRIVATE
            MacOSVideoSupport.hpp
            MacOSVideoSupport.mm
    )
    
    # Link macOS frameworks
    find_library(AVFOUNDATION_FRAMEWORK AVFoundation)
    find_library(VIDEOTOOLBOX_FRAMEWORK VideoToolbox)
    find_library(COREFOUNDATION_FRAMEWORK CoreFoundation)
    find_library(FOUNDATION_FRAMEWORK Foundation)
    
    if(AVFOUNDATION_FRAMEWORK)
        target_link_libraries(${PROJECT_NAME} ${AVFOUNDATION_FRAMEWORK})
        message(STATUS "${MI}Linked AVFoundation framework for video editor")
    endif()
    
    if(VIDEOTOOLBOX_FRAMEWORK)
        target_link_libraries(${PROJECT_NAME} ${VIDEOTOOLBOX_FRAMEWORK})
        message(STATUS "${MI}Linked VideoToolbox framework for video editor")
    endif()
    
    if(COREFOUNDATION_FRAMEWORK)
        target_link_libraries(${PROJECT_NAME} ${COREFOUNDATION_FRAMEWORK})
    endif()
    
    if(FOUNDATION_FRAMEWORK)
        target_link_libraries(${PROJECT_NAME} ${FOUNDATION_FRAMEWORK})
    endif()
    
    # Configure macOS security features
    # **Feature: macos-build-support, Property 15: Security configuration compliance**
    # **Validates: Requirements 8.1, 8.3**
    if(COMMAND configure_macos_security)
        configure_macos_security(${PROJECT_NAME}
            ENABLE_HARDENED_RUNTIME
            ENTITLEMENTS_FILE "${CMAKE_CURRENT_SOURCE_DIR}/VideoEditor.entitlements"
        )
    endif()
    
    # Configure SIP-compatible library loading
    if(COMMAND configure_sip_compatible_loading)
        configure_sip_compatible_loading(${PROJECT_NAME})
    endif()
    
    # Add security compiler flags
    if(COMMAND add_security_compiler_flags)
        add_security_compiler_flags(${PROJECT_NAME})
    endif()
    
    # Add post-build code signing if enabled
    if(COMMAND add_post_build_code_signing)
        add_post_build_code_signing(${PROJECT_NAME})
    endif()
endif()

