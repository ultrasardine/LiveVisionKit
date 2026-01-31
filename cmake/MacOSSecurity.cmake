# MacOSSecurity.cmake
# macOS Security Configuration for OpenVisionKit
# Implements code signing preparation, hardened runtime, and security features
# **Feature: macos-build-support, Property 15: Security configuration compliance**
# **Validates: Requirements 8.1, 8.3**

include(CMakeParseArguments)

# ============================================================================
# Security Configuration Options
# ============================================================================

# Code signing options
option(MACOS_ENABLE_CODE_SIGNING "Enable code signing for macOS builds" OFF)
option(MACOS_ENABLE_HARDENED_RUNTIME "Enable hardened runtime for macOS builds" ON)
option(MACOS_ENABLE_NOTARIZATION_PREP "Prepare binaries for Apple notarization" OFF)

# Security feature options
set(MACOS_CODE_SIGN_IDENTITY "" CACHE STRING "Code signing identity (e.g., 'Developer ID Application: Your Name')")
set(MACOS_TEAM_ID "" CACHE STRING "Apple Developer Team ID for code signing")
set(MACOS_ENTITLEMENTS_FILE "" CACHE STRING "Path to custom entitlements plist file")

# ============================================================================
# Security Configuration Functions
# ============================================================================

# Function to configure macOS security settings for a target
function(configure_macos_security TARGET_NAME)
    if(NOT APPLE)
        return()
    endif()
    
    cmake_parse_arguments(SECURITY
        "ENABLE_HARDENED_RUNTIME;ENABLE_CODE_SIGNING;ENABLE_NOTARIZATION"
        "ENTITLEMENTS_FILE;CODE_SIGN_IDENTITY;TEAM_ID"
        ""
        ${ARGN}
    )
    
    # Default to global settings if not specified
    if(NOT DEFINED SECURITY_ENABLE_HARDENED_RUNTIME)
        set(SECURITY_ENABLE_HARDENED_RUNTIME ${MACOS_ENABLE_HARDENED_RUNTIME})
    endif()
    
    if(NOT DEFINED SECURITY_ENABLE_CODE_SIGNING)
        set(SECURITY_ENABLE_CODE_SIGNING ${MACOS_ENABLE_CODE_SIGNING})
    endif()
    
    if(NOT SECURITY_CODE_SIGN_IDENTITY)
        set(SECURITY_CODE_SIGN_IDENTITY "${MACOS_CODE_SIGN_IDENTITY}")
    endif()
    
    if(NOT SECURITY_TEAM_ID)
        set(SECURITY_TEAM_ID "${MACOS_TEAM_ID}")
    endif()
    
    if(NOT SECURITY_ENTITLEMENTS_FILE)
        set(SECURITY_ENTITLEMENTS_FILE "${MACOS_ENTITLEMENTS_FILE}")
    endif()
    
    # Configure hardened runtime
    if(SECURITY_ENABLE_HARDENED_RUNTIME)
        set_target_properties(${TARGET_NAME} PROPERTIES
            XCODE_ATTRIBUTE_ENABLE_HARDENED_RUNTIME YES
        )
        
        # Add hardened runtime linker flags for non-Xcode builds
        if(NOT CMAKE_GENERATOR MATCHES "Xcode")
            # Generate Info.plist if it doesn't exist
            set(INFO_PLIST_PATH "${CMAKE_CURRENT_BINARY_DIR}/Info.plist")
            if(NOT EXISTS "${INFO_PLIST_PATH}")
                file(WRITE "${INFO_PLIST_PATH}" "<?xml version=\"1.0\" encoding=\"UTF-8\"?>
<!DOCTYPE plist PUBLIC \"-//Apple//DTD PLIST 1.0//EN\" \"http://www.apple.com/DTDs/PropertyList-1.0.dtd\">
<plist version=\"1.0\">
<dict>
    <key>CFBundleExecutable</key>
    <string>${TARGET_NAME}</string>
    <key>CFBundleIdentifier</key>
    <string>com.openvisionkit.${TARGET_NAME}</string>
    <key>CFBundleName</key>
    <string>${TARGET_NAME}</string>
    <key>CFBundleVersion</key>
    <string>1.0</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>LSMinimumSystemVersion</key>
    <string>10.15</string>
</dict>
</plist>")
            endif()
            target_link_options(${TARGET_NAME} PRIVATE
                "LINKER:-sectcreate,__TEXT,__info_plist,${INFO_PLIST_PATH}"
            )
        endif()
        
        message(STATUS "  Hardened runtime enabled for ${TARGET_NAME}")
    endif()
    
    # Configure code signing
    if(SECURITY_ENABLE_CODE_SIGNING AND SECURITY_CODE_SIGN_IDENTITY)
        set_target_properties(${TARGET_NAME} PROPERTIES
            XCODE_ATTRIBUTE_CODE_SIGN_IDENTITY "${SECURITY_CODE_SIGN_IDENTITY}"
            XCODE_ATTRIBUTE_CODE_SIGNING_REQUIRED YES
            XCODE_ATTRIBUTE_CODE_SIGN_STYLE "Manual"
        )
        
        if(SECURITY_TEAM_ID)
            set_target_properties(${TARGET_NAME} PROPERTIES
                XCODE_ATTRIBUTE_DEVELOPMENT_TEAM "${SECURITY_TEAM_ID}"
            )
        endif()
        
        if(SECURITY_ENTITLEMENTS_FILE AND EXISTS "${SECURITY_ENTITLEMENTS_FILE}")
            set_target_properties(${TARGET_NAME} PROPERTIES
                XCODE_ATTRIBUTE_CODE_SIGN_ENTITLEMENTS "${SECURITY_ENTITLEMENTS_FILE}"
            )
        endif()
        
        message(STATUS "  Code signing configured for ${TARGET_NAME}")
    endif()
    
    # Configure for notarization
    if(SECURITY_ENABLE_NOTARIZATION)
        set_target_properties(${TARGET_NAME} PROPERTIES
            XCODE_ATTRIBUTE_ENABLE_HARDENED_RUNTIME YES
            XCODE_ATTRIBUTE_CODE_SIGN_INJECT_BASE_ENTITLEMENTS NO
        )
        
        message(STATUS "  Notarization preparation enabled for ${TARGET_NAME}")
    endif()
endfunction()

# Function to generate default entitlements file for video processing
function(generate_video_processing_entitlements OUTPUT_FILE)
    if(NOT APPLE)
        return()
    endif()
    
    # Create minimal entitlements for video processing applications
    set(ENTITLEMENTS_CONTENT "<?xml version=\"1.0\" encoding=\"UTF-8\"?>
<!DOCTYPE plist PUBLIC \"-//Apple//DTD PLIST 1.0//EN\" \"http://www.apple.com/DTDs/PropertyList-1.0.dtd\">
<plist version=\"1.0\">
<dict>
    <!-- Allow JIT compilation for OpenCV and video processing -->
    <key>com.apple.security.cs.allow-jit</key>
    <true/>
    
    <!-- Allow unsigned executable memory for OpenCL kernels -->
    <key>com.apple.security.cs.allow-unsigned-executable-memory</key>
    <true/>
    
    <!-- Allow loading third-party libraries (OpenCV, Qt, etc.) -->
    <key>com.apple.security.cs.disable-library-validation</key>
    <true/>
    
    <!-- Camera access for video capture (if needed) -->
    <key>com.apple.security.device.camera</key>
    <true/>
    
    <!-- Microphone access for audio capture (if needed) -->
    <key>com.apple.security.device.audio-input</key>
    <true/>
</dict>
</plist>")
    
    file(WRITE "${OUTPUT_FILE}" "${ENTITLEMENTS_CONTENT}")
    message(STATUS "Generated video processing entitlements: ${OUTPUT_FILE}")
endfunction()

# Function to generate OBS plugin entitlements
function(generate_obs_plugin_entitlements OUTPUT_FILE)
    if(NOT APPLE)
        return()
    endif()
    
    # Create entitlements specific to OBS plugins
    set(ENTITLEMENTS_CONTENT "<?xml version=\"1.0\" encoding=\"UTF-8\"?>
<!DOCTYPE plist PUBLIC \"-//Apple//DTD PLIST 1.0//EN\" \"http://www.apple.com/DTDs/PropertyList-1.0.dtd\">
<plist version=\"1.0\">
<dict>
    <!-- Allow JIT compilation for video processing -->
    <key>com.apple.security.cs.allow-jit</key>
    <true/>
    
    <!-- Allow unsigned executable memory for GPU kernels -->
    <key>com.apple.security.cs.allow-unsigned-executable-memory</key>
    <true/>
    
    <!-- Disable library validation for OBS plugin loading -->
    <key>com.apple.security.cs.disable-library-validation</key>
    <true/>
    
    <!-- Allow DYLD environment variables for plugin debugging -->
    <key>com.apple.security.cs.allow-dyld-environment-variables</key>
    <true/>
</dict>
</plist>")
    
    file(WRITE "${OUTPUT_FILE}" "${ENTITLEMENTS_CONTENT}")
    message(STATUS "Generated OBS plugin entitlements: ${OUTPUT_FILE}")
endfunction()

# Function to configure SIP-compatible library loading
function(configure_sip_compatible_loading TARGET_NAME)
    if(NOT APPLE)
        return()
    endif()
    
    # Set rpath for secure library loading
    set_target_properties(${TARGET_NAME} PROPERTIES
        MACOSX_RPATH TRUE
        BUILD_WITH_INSTALL_RPATH TRUE
        INSTALL_RPATH "@loader_path;@executable_path;@loader_path/../Frameworks"
        INSTALL_RPATH_USE_LINK_PATH TRUE
    )
    
    # Ensure proper library identification
    set_target_properties(${TARGET_NAME} PROPERTIES
        INSTALL_NAME_DIR "@rpath"
    )
    
    message(STATUS "  SIP-compatible loading configured for ${TARGET_NAME}")
endfunction()

# Function to add security compiler flags
function(add_security_compiler_flags TARGET_NAME)
    if(NOT APPLE)
        return()
    endif()
    
    # Stack protection
    target_compile_options(${TARGET_NAME} PRIVATE
        -fstack-protector-strong
    )
    
    # Position Independent Code (required for ASLR)
    set_target_properties(${TARGET_NAME} PROPERTIES
        POSITION_INDEPENDENT_CODE ON
    )
    
    # Additional security flags for Release builds
    if(CMAKE_BUILD_TYPE STREQUAL "Release" OR CMAKE_BUILD_TYPE STREQUAL "RelWithDebInfo")
        target_compile_options(${TARGET_NAME} PRIVATE
            -D_FORTIFY_SOURCE=2
        )
        
        # Enable full RELRO (Relocation Read-Only) equivalent on macOS
        target_link_options(${TARGET_NAME} PRIVATE
            "LINKER:-bind_at_load"
        )
    endif()
    
    message(STATUS "  Security compiler flags added for ${TARGET_NAME}")
endfunction()

# Function to validate security configuration
function(validate_security_configuration)
    if(NOT APPLE)
        return()
    endif()
    
    set(SECURITY_WARNINGS "")
    set(SECURITY_ERRORS "")
    
    # Check code signing configuration
    if(MACOS_ENABLE_CODE_SIGNING)
        if(NOT MACOS_CODE_SIGN_IDENTITY)
            list(APPEND SECURITY_WARNINGS "Code signing enabled but no identity specified")
        endif()
        
        if(NOT MACOS_TEAM_ID)
            list(APPEND SECURITY_WARNINGS "Code signing enabled but no Team ID specified")
        endif()
    endif()
    
    # Check notarization requirements
    if(MACOS_ENABLE_NOTARIZATION_PREP)
        if(NOT MACOS_ENABLE_HARDENED_RUNTIME)
            list(APPEND SECURITY_ERRORS "Notarization requires hardened runtime to be enabled")
        endif()
        
        if(NOT MACOS_ENABLE_CODE_SIGNING)
            list(APPEND SECURITY_ERRORS "Notarization requires code signing to be enabled")
        endif()
    endif()
    
    # Check deployment target for security features
    if(CMAKE_OSX_DEPLOYMENT_TARGET VERSION_LESS "10.15")
        list(APPEND SECURITY_WARNINGS "Deployment target ${CMAKE_OSX_DEPLOYMENT_TARGET} may not support all security features")
    endif()
    
    # Report warnings
    foreach(WARNING ${SECURITY_WARNINGS})
        message(WARNING "Security: ${WARNING}")
    endforeach()
    
    # Report errors
    foreach(ERROR ${SECURITY_ERRORS})
        message(FATAL_ERROR "Security: ${ERROR}")
    endforeach()
    
    # Report security configuration status
    message(STATUS "macOS Security Configuration:")
    message(STATUS "  Hardened Runtime: ${MACOS_ENABLE_HARDENED_RUNTIME}")
    message(STATUS "  Code Signing: ${MACOS_ENABLE_CODE_SIGNING}")
    message(STATUS "  Notarization Prep: ${MACOS_ENABLE_NOTARIZATION_PREP}")
    
    if(MACOS_CODE_SIGN_IDENTITY)
        message(STATUS "  Sign Identity: ${MACOS_CODE_SIGN_IDENTITY}")
    endif()
    
    if(MACOS_TEAM_ID)
        message(STATUS "  Team ID: ${MACOS_TEAM_ID}")
    endif()
endfunction()

# ============================================================================
# Post-Build Code Signing Commands
# ============================================================================

# Function to add post-build code signing for non-Xcode builds
function(add_post_build_code_signing TARGET_NAME)
    if(NOT APPLE)
        return()
    endif()
    
    if(NOT MACOS_ENABLE_CODE_SIGNING)
        return()
    endif()
    
    if(NOT MACOS_CODE_SIGN_IDENTITY)
        message(WARNING "Cannot add post-build code signing: no identity specified")
        return()
    endif()
    
    # Build codesign command
    set(CODESIGN_CMD "codesign")
    set(CODESIGN_ARGS "--force" "--sign" "${MACOS_CODE_SIGN_IDENTITY}")
    
    if(MACOS_ENABLE_HARDENED_RUNTIME)
        list(APPEND CODESIGN_ARGS "--options" "runtime")
    endif()
    
    if(MACOS_ENTITLEMENTS_FILE AND EXISTS "${MACOS_ENTITLEMENTS_FILE}")
        list(APPEND CODESIGN_ARGS "--entitlements" "${MACOS_ENTITLEMENTS_FILE}")
    endif()
    
    # Add timestamp for notarization
    if(MACOS_ENABLE_NOTARIZATION_PREP)
        list(APPEND CODESIGN_ARGS "--timestamp")
    endif()
    
    add_custom_command(TARGET ${TARGET_NAME} POST_BUILD
        COMMAND ${CODESIGN_CMD} ${CODESIGN_ARGS} "$<TARGET_FILE:${TARGET_NAME}>"
        COMMENT "Code signing ${TARGET_NAME}..."
        VERBATIM
    )
    
    message(STATUS "  Post-build code signing configured for ${TARGET_NAME}")
endfunction()

# ============================================================================
# Security Verification Functions
# ============================================================================

# Function to verify code signature (for testing)
function(verify_code_signature BINARY_PATH OUTPUT_VAR)
    if(NOT APPLE)
        set(${OUTPUT_VAR} FALSE PARENT_SCOPE)
        return()
    endif()
    
    execute_process(
        COMMAND codesign --verify --verbose=2 "${BINARY_PATH}"
        RESULT_VARIABLE VERIFY_RESULT
        OUTPUT_VARIABLE VERIFY_OUTPUT
        ERROR_VARIABLE VERIFY_ERROR
    )
    
    if(VERIFY_RESULT EQUAL 0)
        set(${OUTPUT_VAR} TRUE PARENT_SCOPE)
    else()
        set(${OUTPUT_VAR} FALSE PARENT_SCOPE)
        message(STATUS "Code signature verification failed: ${VERIFY_ERROR}")
    endif()
endfunction()

# Function to check hardened runtime status
function(check_hardened_runtime BINARY_PATH OUTPUT_VAR)
    if(NOT APPLE)
        set(${OUTPUT_VAR} FALSE PARENT_SCOPE)
        return()
    endif()
    
    execute_process(
        COMMAND codesign --display --verbose=4 "${BINARY_PATH}"
        OUTPUT_VARIABLE CODESIGN_OUTPUT
        ERROR_VARIABLE CODESIGN_ERROR
    )
    
    # Check for runtime flag in output
    if(CODESIGN_ERROR MATCHES "flags=.*runtime")
        set(${OUTPUT_VAR} TRUE PARENT_SCOPE)
    else()
        set(${OUTPUT_VAR} FALSE PARENT_SCOPE)
    endif()
endfunction()

# ============================================================================
# Initialization
# ============================================================================

# Validate security configuration when this module is included
if(APPLE)
    validate_security_configuration()
endif()
