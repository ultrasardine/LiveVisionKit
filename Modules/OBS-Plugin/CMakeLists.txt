
# Set up project 
project(lvk-obs VERSION 1.3.0 LANGUAGES CXX)
set(CMAKE_CXX_STANDARD 20)


# Set up library 
add_library(${PROJECT_NAME} SHARED)

set_property(TARGET ${PROJECT_NAME} PROPERTY PROJECT_LABEL "OBS-Plugin")
set_property(TARGET ${PROJECT_NAME} PROPERTY INTERPROCEDURAL_OPTIMIZATION TRUE)
set_property(TARGET ${PROJECT_NAME} PROPERTY MSVC_RUNTIME_LIBRARY "MultiThreaded$<$<CONFIG:Debug>:Debug>")

# Configure macOS-specific library properties
if(APPLE)
    set_target_properties(${PROJECT_NAME} PROPERTIES
        PREFIX ""
        SUFFIX ""
        BUNDLE FALSE
        MACOSX_RPATH TRUE
        INSTALL_RPATH "@loader_path"
    )
    
    # Configure macOS security features
    # **Feature: macos-build-support, Property 15: Security configuration compliance**
    # **Validates: Requirements 8.1, 8.3**
    if(COMMAND configure_macos_security)
        configure_macos_security(${PROJECT_NAME}
            ENABLE_HARDENED_RUNTIME
            ENTITLEMENTS_FILE "${CMAKE_CURRENT_SOURCE_DIR}/Data/OpenVisionKit.entitlements"
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

# Disable assert checks
if(DISABLE_CHECKS)
    add_definitions(-DLVK_DISABLE_CHECKS)
    add_definitions(-DNDEBUG)
endif()

# Define the plugin version
add_definitions(-DVERSION="${PROJECT_VERSION}")
message(STATUS "${MI}Plugin Version: ${PROJECT_VERSION}")

# Project settings
option(OBS_PLUGIN_SHOW_LOCALE_TAG "Show locale tags for translations" "OFF")
if(OBS_PLUGIN_SHOW_LOCALE_TAG)
    add_definitions(-DLOCALE_SHOW_TAG)
endif()
message(STATUS "${MI}Show Locale Tags: ${OBS_PLUGIN_SHOW_LOCALE_TAG}")

option(OBS_PLUGIN_PRINT_SETTINGS "Print filter settings when changed (for debug)" "OFF")
if(OBS_PLUGIN_PRINT_SETTINGS)
    add_definitions(-DPRINT_SETTINGS)
endif()
message(STATUS "${MI}Print Settings: ${OBS_PLUGIN_PRINT_SETTINGS}")

if(UNIX)
    option(OBS_PLUGIN_FAST_DMA "Use experimental OpenGL operations for faster DMA" "OFF")
    if(OBS_PLUGIN_FAST_DMA)
        add_definitions(-DFAST_GL_DMA)
    endif()
    message(STATUS "${MI}Faster OpenGL DMA: ${OBS_PLUGIN_FAST_DMA}")
endif()

# Install settings
option(
    OBS_PLUGIN_AUTO_INSTALL 
    "Automatically install the plugin into the given obs-studio folders (RELEASE ONLY)"
)
if(WIN32)
    set(
        OBS_PLUGIN_AUTO_INSTALL_PATHS 
        "C:/Program Files/obs-studio" 
        CACHE PATH 
        "The plugin auto-install paths, leading to the root obs-studio directory"
    )
elseif(APPLE)
    set(
        OBS_PLUGIN_AUTO_INSTALL_PATHS 
        "~/Library/Application Support/obs-studio" 
        CACHE PATH 
        "The plugin auto-install paths, leading to the root obs-studio directory"
    )
else()
    set(
        OBS_PLUGIN_AUTO_INSTALL_PATHS 
        "~/.config/obs-studio" 
        CACHE PATH 
        "The plugin auto-install paths, leading to the root obs-studio directory"
    )
endif()


# OBS Studio Detection - Support both system and custom installations
set(OBS_BUILD_PATH "./Dependencies/obs-studio/build" CACHE PATH "The path to the OBS-Studio build folder")

# Try to find OBS Studio using pkg-config first (Linux/macOS system installations)
find_package(PkgConfig QUIET)
if(PKG_CONFIG_FOUND)
    pkg_check_modules(OBS_STUDIO QUIET libobs)
endif()

# Set up OBS paths based on detection method
set(OBS_FOUND FALSE)
set(OBS_INCLUDE_DIRS "")
set(OBS_LIBRARIES "")

if(OBS_STUDIO_FOUND)
    # System installation found via pkg-config
    set(OBS_FOUND TRUE)
    set(OBS_INCLUDE_DIRS ${OBS_STUDIO_INCLUDE_DIRS})
    set(OBS_LIBRARIES ${OBS_STUDIO_LIBRARIES})
    message(STATUS "${MI}Found OBS-Studio via pkg-config: YES")
    message(STATUS "${MI}OBS Include Dirs: ${OBS_INCLUDE_DIRS}")
    message(STATUS "${MI}OBS Libraries: ${OBS_LIBRARIES}")
elseif(APPLE AND EXISTS "/opt/homebrew/include/obs" AND EXISTS "/opt/homebrew/lib/libobs.dylib")
    # macOS Homebrew installation
    set(OBS_FOUND TRUE)
    set(OBS_INCLUDE_DIRS "/opt/homebrew/include/obs")
    set(OBS_LIBRARIES "/opt/homebrew/lib/libobs.dylib")
    message(STATUS "${MI}Found OBS-Studio via Homebrew: YES")
elseif(APPLE AND EXISTS "/usr/local/include/obs" AND EXISTS "/usr/local/lib/libobs.dylib")
    # macOS Intel Homebrew installation
    set(OBS_FOUND TRUE)
    set(OBS_INCLUDE_DIRS "/usr/local/include/obs")
    set(OBS_LIBRARIES "/usr/local/lib/libobs.dylib")
    message(STATUS "${MI}Found OBS-Studio via Intel Homebrew: YES")
else()
    # Fall back to custom build path
    if(WIN32)
        set(OBS_REL_INCLUDE_PATH "/install/include/")
        set(OBS_REL_LIB_PATH "/install/bin/64bit/obs.lib")
    elseif(APPLE)
        # OBS 32+ on macOS builds as framework in app bundle
        # Headers are in source tree, library is in framework
        set(OBS_REL_INCLUDE_PATH "/install/include/obs/")
        set(OBS_REL_LIB_PATH "/install/lib/libobs.dylib")
        # Alternative paths for OBS 32+ framework build
        set(OBS_SOURCE_INCLUDE_PATH "/../libobs/")
        set(OBS_FRAMEWORK_LIB_PATH "/install/OBS.app/Contents/Frameworks/libobs.framework/libobs")
    else()
        set(OBS_REL_INCLUDE_PATH "/install/include/obs/")
        set(OBS_REL_LIB_PATH "/install/lib/libobs.so")
    endif()

    # Check that the build path exists
    if(OBS_BUILD_PATH STREQUAL "")
        message(FATAL_ERROR "OBS_BUILD_PATH was not provided and system OBS not found!")
    else()
        # Convert to absolute path and normalize
        get_filename_component(OBS_BUILD_PATH_ABS "${OBS_BUILD_PATH}" ABSOLUTE)
        message(STATUS "${MI}OBS_BUILD_PATH (absolute): ${OBS_BUILD_PATH_ABS}")
        
        # First try traditional layout
        if(EXISTS ${OBS_BUILD_PATH_ABS}${OBS_REL_INCLUDE_PATH} AND EXISTS ${OBS_BUILD_PATH_ABS}${OBS_REL_LIB_PATH})
            set(OBS_FOUND TRUE)
            set(OBS_INCLUDE_DIRS "${OBS_BUILD_PATH_ABS}${OBS_REL_INCLUDE_PATH}")
            set(OBS_LIBRARIES "${OBS_BUILD_PATH_ABS}${OBS_REL_LIB_PATH}")
            message(STATUS "${MI}Found OBS-Studio via custom build: YES")
        else()
            # macOS: Try OBS 32+ framework layout (headers in source, lib in app bundle)
            if(APPLE)
                # OBS_BUILD_PATH might be .../build or .../build/install - handle both
                # Get OBS source root by going up to find libobs directory
                set(OBS_SOURCE_ROOT "${OBS_BUILD_PATH_ABS}")
                # If path ends with /install, go up one level to get build dir
                if(OBS_BUILD_PATH_ABS MATCHES ".*/install$")
                    get_filename_component(OBS_SOURCE_ROOT "${OBS_BUILD_PATH_ABS}" DIRECTORY)
                endif()
                # Go up one more level to get obs-studio source root
                get_filename_component(OBS_SOURCE_ROOT "${OBS_SOURCE_ROOT}" DIRECTORY)
                
                set(OBS_FRAMEWORK_INCLUDE "${OBS_SOURCE_ROOT}/libobs")
                # Also need the generated config headers from the build directory
                set(OBS_GENERATED_INCLUDE "${OBS_SOURCE_ROOT}/build_macos/config")
                # Handle both possible locations for the framework
                set(OBS_FRAMEWORK_LIBRARY "${OBS_BUILD_PATH_ABS}/OBS.app/Contents/Frameworks/libobs.framework/libobs")
                if(NOT EXISTS "${OBS_FRAMEWORK_LIBRARY}")
                    set(OBS_FRAMEWORK_LIBRARY "${OBS_SOURCE_ROOT}/build/install/OBS.app/Contents/Frameworks/libobs.framework/libobs")
                endif()
                
                message(STATUS "${MI}Checking OBS framework paths:")
                message(STATUS "${MI}  Include: ${OBS_FRAMEWORK_INCLUDE}")
                message(STATUS "${MI}  Library: ${OBS_FRAMEWORK_LIBRARY}")
                
                if(EXISTS "${OBS_FRAMEWORK_INCLUDE}/obs.h" AND EXISTS "${OBS_FRAMEWORK_LIBRARY}")
                    set(OBS_FOUND TRUE)
                    # Include both source headers and generated config headers
                    set(OBS_INCLUDE_DIRS "${OBS_FRAMEWORK_INCLUDE}" "${OBS_GENERATED_INCLUDE}")
                    set(OBS_LIBRARIES "${OBS_FRAMEWORK_LIBRARY}")
                    message(STATUS "${MI}Found OBS-Studio via macOS framework build: YES")
                    message(STATUS "${MI}OBS Generated headers: ${OBS_GENERATED_INCLUDE}")
                endif()
            endif()
        endif()
        
        if(NOT OBS_FOUND)
            message(FATAL_ERROR "Could not find OBS-Studio includes or libraries - Check OBS_BUILD_PATH or install system OBS")
        endif()
    endif()
endif()

if(NOT OBS_FOUND)
    message(FATAL_ERROR "OBS Studio not found! Please install obs-studio-dev (Linux) or obs-studio (macOS) or provide OBS_BUILD_PATH")
endif()

# OBS Version Detection and Compatibility
function(detect_obs_version OBS_INCLUDE_PATH OUTPUT_VAR)
    # Try different possible locations for obs-config.h
    set(POSSIBLE_CONFIG_FILES
        "${OBS_INCLUDE_PATH}/obs-config.h"
        "${OBS_INCLUDE_PATH}/../include/obs/obs-config.h"
        "${OBS_INCLUDE_PATH}/obs/obs-config.h"
    )
    
    set(OBS_VERSION_FILE "")
    foreach(CONFIG_FILE ${POSSIBLE_CONFIG_FILES})
        if(EXISTS ${CONFIG_FILE})
            set(OBS_VERSION_FILE ${CONFIG_FILE})
            break()
        endif()
    endforeach()
    
    if(OBS_VERSION_FILE AND EXISTS ${OBS_VERSION_FILE})
        file(READ ${OBS_VERSION_FILE} OBS_CONFIG_CONTENT)
        
        # Extract version from OBS_VERSION_CANONICAL or similar defines
        string(REGEX MATCH "#define[ \t]+OBS_VERSION_CANONICAL[ \t]+\"([0-9]+\\.[0-9]+\\.[0-9]+)\"" 
               VERSION_MATCH "${OBS_CONFIG_CONTENT}")
        
        if(VERSION_MATCH)
            string(REGEX REPLACE "#define[ \t]+OBS_VERSION_CANONICAL[ \t]+\"([0-9]+\\.[0-9]+\\.[0-9]+)\"" 
                   "\\1" DETECTED_VERSION "${VERSION_MATCH}")
            set(${OUTPUT_VAR} ${DETECTED_VERSION} PARENT_SCOPE)
        else()
            # Fallback: try to extract from OBS_VERSION_MAJOR/MINOR/PATCH
            string(REGEX MATCH "#define[ \t]+OBS_VERSION_MAJOR[ \t]+([0-9]+)" MAJOR_MATCH "${OBS_CONFIG_CONTENT}")
            string(REGEX MATCH "#define[ \t]+OBS_VERSION_MINOR[ \t]+([0-9]+)" MINOR_MATCH "${OBS_CONFIG_CONTENT}")
            string(REGEX MATCH "#define[ \t]+OBS_VERSION_PATCH[ \t]+([0-9]+)" PATCH_MATCH "${OBS_CONFIG_CONTENT}")
            
            if(MAJOR_MATCH AND MINOR_MATCH AND PATCH_MATCH)
                string(REGEX REPLACE "#define[ \t]+OBS_VERSION_MAJOR[ \t]+([0-9]+)" "\\1" MAJOR "${MAJOR_MATCH}")
                string(REGEX REPLACE "#define[ \t]+OBS_VERSION_MINOR[ \t]+([0-9]+)" "\\1" MINOR "${MINOR_MATCH}")
                string(REGEX REPLACE "#define[ \t]+OBS_VERSION_PATCH[ \t]+([0-9]+)" "\\1" PATCH "${PATCH_MATCH}")
                set(${OUTPUT_VAR} "${MAJOR}.${MINOR}.${PATCH}" PARENT_SCOPE)
            else()
                set(${OUTPUT_VAR} "unknown" PARENT_SCOPE)
            endif()
        endif()
    else()
        # Try to get version from pkg-config if available
        if(PKG_CONFIG_FOUND AND OBS_STUDIO_FOUND)
            set(${OUTPUT_VAR} ${OBS_STUDIO_VERSION} PARENT_SCOPE)
        else()
            set(${OUTPUT_VAR} "unknown" PARENT_SCOPE)
        endif()
    endif()
endfunction()

# Detect OBS version using the include directory
detect_obs_version("${OBS_INCLUDE_DIRS}" OBS_DETECTED_VERSION)
message(STATUS "${MI}OBS Studio Version: ${OBS_DETECTED_VERSION}")

# Define minimum supported OBS version
set(OBS_MIN_VERSION "29.0.0")
set(OBS_MAX_TESTED_VERSION "32.0.4")

# Version compatibility check
if(NOT OBS_DETECTED_VERSION STREQUAL "unknown")
    if(OBS_DETECTED_VERSION VERSION_LESS OBS_MIN_VERSION)
        message(WARNING "OBS Studio version ${OBS_DETECTED_VERSION} is older than minimum supported version ${OBS_MIN_VERSION}. Plugin may not work correctly.")
    elseif(OBS_DETECTED_VERSION VERSION_GREATER OBS_MAX_TESTED_VERSION)
        message(WARNING "OBS Studio version ${OBS_DETECTED_VERSION} is newer than tested version ${OBS_MAX_TESTED_VERSION}. Plugin compatibility is not guaranteed.")
    else()
        message(STATUS "${MI}OBS Studio version is compatible")
    endif()
endif()

# Set compatibility flags based on OBS version
if(OBS_DETECTED_VERSION VERSION_GREATER_EQUAL "30.0.0")
    add_definitions(-DOBS_VERSION_30_PLUS)
    message(STATUS "${MI}Enabling OBS 30+ compatibility features")
endif()

if(OBS_DETECTED_VERSION VERSION_GREATER_EQUAL "29.1.0")
    add_definitions(-DOBS_VERSION_29_1_PLUS)
endif()

# macOS-specific OBS compatibility
if(APPLE)
    # Handle macOS-specific OBS API differences
    if(OBS_DETECTED_VERSION VERSION_GREATER_EQUAL "30.0.0")
        add_definitions(-DOBS_MACOS_METAL_SUPPORT)
        message(STATUS "${MI}Enabling macOS Metal support for OBS 30+")
    endif()
    
    # Set macOS deployment target based on OBS requirements
    if(OBS_DETECTED_VERSION VERSION_GREATER_EQUAL "30.0.0")
        set(CMAKE_OSX_DEPLOYMENT_TARGET "11.0" CACHE STRING "Minimum macOS version for OBS 30+")
    else()
        set(CMAKE_OSX_DEPLOYMENT_TARGET "10.15" CACHE STRING "Minimum macOS version for OBS 29.x")
    endif()
    
    message(STATUS "${MI}macOS Deployment Target: ${CMAKE_OSX_DEPLOYMENT_TARGET}")
endif()


# Find SIMDE for ARM64 SSE emulation (required by OBS on Apple Silicon)
if(APPLE AND CMAKE_SYSTEM_PROCESSOR MATCHES "arm64")
    # Try to find SIMDE via Homebrew
    execute_process(
        COMMAND brew --prefix simde
        OUTPUT_VARIABLE SIMDE_PREFIX
        OUTPUT_STRIP_TRAILING_WHITESPACE
        ERROR_QUIET
    )
    if(EXISTS "${SIMDE_PREFIX}/include/simde")
        set(SIMDE_INCLUDE_DIR "${SIMDE_PREFIX}/include")
        message(STATUS "${MI}Found SIMDE: ${SIMDE_INCLUDE_DIR}")
    else()
        message(WARNING "SIMDE not found. Install with: brew install simde")
    endif()
endif()

# Include all dependencies
target_include_directories(
    ${PROJECT_NAME}
    PRIVATE
    ${CMAKE_CURRENT_SOURCE_DIR} 
    ${LVK_CORE_DIR}
    ${OBS_INCLUDE_DIRS}
    ${SIMDE_INCLUDE_DIR}
)

# Link all dependencies
add_dependencies(${PROJECT_NAME} lvk-core)
target_link_libraries(
    ${PROJECT_NAME}
    ${OBS_LIBRARIES}
    lvk-core
)


# Set up install rules
set(PLUGIN_RELEASE_NAME "OpenVisionKit-${PROJECT_VERSION}-${CMAKE_SYSTEM_NAME}")
set(PLUGIN_DEBUG_RELEASE_NAME "DEBUG_${PLUGIN_RELEASE_NAME}")

set(PLUGIN_RELEASE_ROOT_DIR "${LVK_RELEASES_DIR}/${PLUGIN_RELEASE_NAME}/obs-studio")
set(PLUGIN_DEBUG_RELEASE_ROOT_DIR "${LVK_RELEASES_DIR}/${PLUGIN_DEBUG_RELEASE_NAME}/obs-studio")

set(PLUGIN_RELEASE_INSTALL_DIRS "${CMAKE_INSTALL_PREFIX}/${PLUGIN_RELEASE_ROOT_DIR}")
if(OBS_PLUGIN_AUTO_INSTALL)
    list(APPEND PLUGIN_RELEASE_INSTALL_DIRS ${OBS_PLUGIN_AUTO_INSTALL_PATHS})
endif()

message(STATUS "${MI}Auto-Install Plugin: " ${OBS_PLUGIN_AUTO_INSTALL})
message(STATUS "${MI}Install Paths:" )
message(STATUS "${MI}${MI} (DEBUG) ${CMAKE_INSTALL_PREFIX}/${PLUGIN_DEBUG_RELEASE_ROOT_DIR}")
foreach(INSTALL_DIR ${PLUGIN_RELEASE_INSTALL_DIRS})
    message(STATUS "${MI}${MI} (RELEASE) ${INSTALL_DIR}")
endforeach()

if(WIN32)
    set(PLUGIN_RELEASE_BIN_DIR "/obs-plugins/64bit") 
    set(PLUGIN_RELEASE_DATA_DIR "/data/obs-plugins/${PROJECT_NAME}") 

    # Optimized
    foreach(INSTALL_DIR ${PLUGIN_RELEASE_INSTALL_DIRS})
        install(
            TARGETS ${PROJECT_NAME}
            CONFIGURATIONS Release MinSizeRel RelWithDebInfo
            RUNTIME DESTINATION "${INSTALL_DIR}${PLUGIN_RELEASE_BIN_DIR}"
        )
        install(
            DIRECTORY ${CMAKE_CURRENT_SOURCE_DIR}/Data/
            CONFIGURATIONS Release MinSizeRel RelWithDebInfo
            DESTINATION "${INSTALL_DIR}${PLUGIN_RELEASE_DATA_DIR}"
        )
    endforeach()
    
    # Debug
    install(
        TARGETS ${PROJECT_NAME}
        CONFIGURATIONS Debug
        RUNTIME DESTINATION "${PLUGIN_DEBUG_RELEASE_ROOT_DIR}${PLUGIN_RELEASE_BIN_DIR}"
    )
    install(
        DIRECTORY ${CMAKE_CURRENT_SOURCE_DIR}/Data/
        CONFIGURATIONS Debug
        DESTINATION "${PLUGIN_DEBUG_RELEASE_ROOT_DIR}${PLUGIN_RELEASE_DATA_DIR}"
    )
elseif(APPLE)
    # macOS OBS plugin structure: plugins/plugin-name.plugin/Contents/MacOS/ for binaries
    # and plugins/plugin-name.plugin/Contents/Resources/ for data
    set(PLUGIN_RELEASE_BIN_DIR "/plugins/${PROJECT_NAME}.plugin/Contents/MacOS") 
    set(PLUGIN_RELEASE_DATA_DIR "/plugins/${PROJECT_NAME}.plugin/Contents/Resources") 

    # Optimized
    foreach(INSTALL_DIR ${PLUGIN_RELEASE_INSTALL_DIRS})
        install(
            TARGETS ${PROJECT_NAME}
            CONFIGURATIONS Release MinSizeRel RelWithDebInfo
            LIBRARY DESTINATION "${INSTALL_DIR}${PLUGIN_RELEASE_BIN_DIR}"
        )
        install(
            DIRECTORY ${CMAKE_CURRENT_SOURCE_DIR}/Data/
            CONFIGURATIONS Release MinSizeRel RelWithDebInfo
            DESTINATION "${INSTALL_DIR}${PLUGIN_RELEASE_DATA_DIR}"
        )
        # Install Info.plist for macOS bundle structure
        install(
            FILES ${CMAKE_CURRENT_SOURCE_DIR}/Data/Info.plist
            CONFIGURATIONS Release MinSizeRel RelWithDebInfo
            DESTINATION "${INSTALL_DIR}/plugins/${PROJECT_NAME}.plugin/Contents"
        )
    endforeach()

    # Debug
    install(
        TARGETS ${PROJECT_NAME}
        CONFIGURATIONS Debug
        LIBRARY DESTINATION "${PLUGIN_DEBUG_RELEASE_ROOT_DIR}${PLUGIN_RELEASE_BIN_DIR}"
    )
    install(
        DIRECTORY ${CMAKE_CURRENT_SOURCE_DIR}/Data/
        CONFIGURATIONS Debug
        DESTINATION "${PLUGIN_DEBUG_RELEASE_ROOT_DIR}${PLUGIN_RELEASE_DATA_DIR}"
    )
    # Install Info.plist for debug builds
    install(
        FILES ${CMAKE_CURRENT_SOURCE_DIR}/Data/Info.plist
        CONFIGURATIONS Debug
        DESTINATION "${PLUGIN_DEBUG_RELEASE_ROOT_DIR}/plugins/${PROJECT_NAME}.plugin/Contents"
    )
else()
    set(PLUGIN_RELEASE_BIN_DIR "/plugins/${PROJECT_NAME}/bin/64bit") 
    set(PLUGIN_RELEASE_DATA_DIR "/plugins/${PROJECT_NAME}/data") 

    # Optimized
    foreach(INSTALL_DIR ${PLUGIN_RELEASE_INSTALL_DIRS})
        install(
            TARGETS ${PROJECT_NAME}
            CONFIGURATIONS Release MinSizeRel RelWithDebInfo
            DESTINATION "${INSTALL_DIR}${PLUGIN_RELEASE_BIN_DIR}"
        )
        install(
            DIRECTORY ${CMAKE_CURRENT_SOURCE_DIR}/Data/
            CONFIGURATIONS Release MinSizeRel RelWithDebInfo
            DESTINATION "${INSTALL_DIR}${PLUGIN_RELEASE_DATA_DIR}"
        )
    endforeach()

    # Debug
    install(
        TARGETS ${PROJECT_NAME}
        CONFIGURATIONS Debug
        DESTINATION "${PLUGIN_DEBUG_RELEASE_ROOT_DIR}${PLUGIN_RELEASE_BIN_DIR}"
    )
    install(
        DIRECTORY ${CMAKE_CURRENT_SOURCE_DIR}/Data/
        CONFIGURATIONS Debug
        DESTINATION "${PLUGIN_DEBUG_RELEASE_ROOT_DIR}${PLUGIN_RELEASE_DATA_DIR}"
    )
endif()


# Add library sources
target_sources(
    ${PROJECT_NAME}
    PRIVATE
        Sources/Module.cpp
        Sources/Enhancement/ADBFilter.cpp
        Sources/Enhancement/ADBFilter.hpp
        Sources/Enhancement/ADBSource.cpp
        Sources/Enhancement/CASFilter.cpp
        Sources/Enhancement/CASFilter.hpp
        Sources/Enhancement/CASSource.cpp
        Sources/Enhancement/LCFilter.cpp
        Sources/Enhancement/LCFilter.hpp
        Sources/Enhancement/LCSource.cpp
        Sources/Scaling/FSRFilter.cpp
        Sources/Scaling/FSRFilter.hpp
        Sources/Scaling/FSRSource.cpp
        Sources/Stabilisation/VSFilter.cpp
        Sources/Stabilisation/VSFilter.hpp
        Sources/Stabilisation/VSSource.cpp
        Sources/Tools/CCSource.cpp
        Sources/Tools/CCTool.cpp
        Sources/Tools/CCTool.hpp

        Sources/Tools/IngestTestFilter.cpp
        Sources/Tools/IngestTestFilter.hpp
        Sources/Tools/IngestTestSource.cpp

        Data/effects/ffx_a.h
        Data/effects/ffx_a_mod.h
        Data/effects/ffx_cas.h
        Data/effects/ffx_cas_mod.h
        Data/effects/ffx_fsr1.h
        Data/effects/ffx_fsr1_mod.h
        Effects/CASEffect.cpp
        Effects/CASEffect.hpp
        Effects/DefaultEffect.cpp
        Effects/DefaultEffect.hpp
        Effects/FSREffect.cpp
        Effects/FSREffect.hpp
        Effects/OBSEffect.hpp
        Effects/OBSEffect.tpp

        Interop/OBSFrame.cpp
        Interop/OBSFrame.hpp
        Interop/FrameIngest.cpp
        Interop/FrameIngest.hpp
        Interop/InteropContext.cpp
        Interop/InteropContext.hpp
        Interop/VisionFilter.cpp
        Interop/VisionFilter.hpp

        Utility/Graphics.cpp
        Utility/Graphics.hpp
        Utility/Locale.hpp
        Utility/Logging.hpp
        Utility/Logging.tpp
        Utility/OBSDispatch.hpp
        Utility/OBSDispatch.tpp
        Utility/OBSCompatibility.hpp
        Utility/ScopedProfiler.hpp
        Utility/ScopedProfiler.cpp

        Utility/3rdParty/glad.h
        Utility/3rdParty/glad.c
        Utility/3rdParty/khrplatform.h
)
