#!/bin/bash

# OpenVisionKit macOS Build Script
# Automated building with configuration options and parameter handling

set -e  # Exit on any error

# Default configuration values
config="Release"
architecture="universal"  # x86_64, arm64, or universal
macos_version="10.15"
build_plugin=false
build_editor=false
install_plugin=false
enable_testing=false
enable_code_signing=false
verbose=false
clean_build=false
parallel_jobs=$(sysctl -n hw.ncpu)
install_prefix=""
create_package=false
package_format="dmg"  # dmg, pkg, or zip
package_name=""

# Parse command line arguments
while getopts "c:a:m:peitsvj:P:Ckf:n:h" args; do
    case $args in
        c)
            config=${OPTARG}
            ;;
        a)
            architecture=${OPTARG}
            ;;
        m)
            macos_version=${OPTARG}
            ;;
        p)
            build_plugin=true
            ;;
        e)
            build_editor=true
            ;;
        i)
            install_plugin=true
            ;;
        t)
            enable_testing=true
            ;;
        s)
            enable_code_signing=true
            ;;
        v)
            verbose=true
            ;;
        j)
            parallel_jobs=${OPTARG}
            ;;
        P)
            install_prefix=${OPTARG}
            ;;
        C)
            clean_build=true
            ;;
        k)
            create_package=true
            ;;
        f)
            package_format=${OPTARG}
            ;;
        n)
            package_name=${OPTARG}
            ;;
        h)
            echo "Usage: $0 [options]"
            echo ""
            echo "Build Configuration Options:"
            echo "  -c config        Build configuration (Release/Debug/RelWithDebInfo, default: Release)"
            echo "  -a arch          Target architecture (x86_64/arm64/universal, default: universal)"
            echo "  -m version       Minimum macOS version (default: 10.15)"
            echo ""
            echo "Component Options:"
            echo "  -p               Build OBS plugin"
            echo "  -e               Build video editor"
            echo "  -i               Auto-install OBS plugin to system location"
            echo "  -t               Enable testing"
            echo ""
            echo "Build Options:"
            echo "  -s               Enable code signing preparation"
            echo "  -v               Verbose output"
            echo "  -j jobs          Number of parallel build jobs (default: CPU count)"
            echo "  -P prefix        Installation prefix (default: ./Install)"
            echo "  -C               Clean build (remove existing build directory)"
            echo ""
            echo "Packaging Options:"
            echo "  -k               Create distribution package"
            echo "  -f format        Package format (dmg/pkg/zip, default: dmg)"
            echo "  -n name          Package name (default: auto-generated)"
            echo ""
            echo "  -h               Show this help message"
            echo ""
            echo "Examples:"
            echo "  $0 -c Release -p -e              # Build release with plugin and editor"
            echo "  $0 -c Debug -t -v                # Debug build with tests and verbose output"
            echo "  $0 -a arm64 -m 11.0 -s           # ARM64 build for macOS 11.0+ with code signing"
            echo "  $0 -C -c Release -p -i           # Clean release build with plugin auto-install"
            echo "  $0 -c Release -p -e -k -f dmg   # Release build with packaging as DMG"
            exit 0
            ;;
        *)
            echo "Error: Invalid option. Use -h for help."
            exit 1
            ;;
    esac
done

# Logging functions
log_info() {
    echo "[INFO] $1"
}

log_error() {
    echo "[ERROR] $1" >&2
}

log_verbose() {
    if [ "$verbose" = true ]; then
        echo "[VERBOSE] $1"
    fi
}

log_success() {
    echo "[SUCCESS] $1"
}

# Validation functions
validate_configuration() {
    log_info "Validating build configuration..."
    
    # Validate build configuration
    case "$config" in
        "Release"|"Debug"|"RelWithDebInfo")
            log_verbose "Build configuration: $config"
            ;;
        *)
            log_error "Invalid build configuration: $config"
            log_error "Valid options: Release, Debug, RelWithDebInfo"
            exit 1
            ;;
    esac
    
    # Validate architecture
    case "$architecture" in
        "x86_64"|"arm64"|"universal")
            log_verbose "Target architecture: $architecture"
            ;;
        *)
            log_error "Invalid architecture: $architecture"
            log_error "Valid options: x86_64, arm64, universal"
            exit 1
            ;;
    esac
    
    # Validate macOS version
    if [[ ! "$macos_version" =~ ^[0-9]+\.[0-9]+$ ]]; then
        log_error "Invalid macOS version format: $macos_version"
        log_error "Expected format: X.Y (e.g., 10.15, 11.0, 12.0)"
        exit 1
    fi
    
    # Check minimum supported version
    local major=$(echo "$macos_version" | cut -d. -f1)
    local minor=$(echo "$macos_version" | cut -d. -f2)
    
    if [ "$major" -lt 10 ] || ([ "$major" -eq 10 ] && [ "$minor" -lt 15 ]); then
        log_error "macOS version $macos_version is not supported"
        log_error "Minimum supported version: 10.15"
        exit 1
    fi
    
    # Validate parallel jobs
    if ! [[ "$parallel_jobs" =~ ^[0-9]+$ ]] || [ "$parallel_jobs" -lt 1 ]; then
        log_error "Invalid number of parallel jobs: $parallel_jobs"
        log_error "Must be a positive integer"
        exit 1
    fi
    
    # Validate package format
    if [ "$create_package" = true ]; then
        case "$package_format" in
            "dmg"|"pkg"|"zip")
                log_verbose "Package format: $package_format"
                ;;
            *)
                log_error "Invalid package format: $package_format"
                log_error "Valid options: dmg, pkg, zip"
                exit 1
                ;;
        esac
    fi
    
    log_verbose "Configuration validation passed"
}

# System detection and validation
detect_system_capabilities() {
    log_info "Detecting system capabilities..."
    
    # Check macOS version
    local system_version=$(sw_vers -productVersion)
    log_info "System macOS version: $system_version"
    
    # Check architecture
    local system_arch=$(uname -m)
    log_info "System architecture: $system_arch"
    
    # Validate architecture compatibility
    if [ "$architecture" = "arm64" ] && [ "$system_arch" = "x86_64" ]; then
        log_error "Cannot build ARM64 binaries on Intel Mac without Rosetta 2"
        log_error "Use 'universal' architecture or build on Apple Silicon Mac"
        exit 1
    fi
    
    # Check available CPU cores
    local available_cores=$(sysctl -n hw.ncpu)
    log_info "Available CPU cores: $available_cores"
    
    if [ "$parallel_jobs" -gt "$available_cores" ]; then
        log_verbose "Requested jobs ($parallel_jobs) exceeds available cores ($available_cores)"
        log_verbose "This may impact system performance"
    fi
    
    # Check available memory
    local available_memory_gb=$(($(sysctl -n hw.memsize) / 1024 / 1024 / 1024))
    log_info "Available memory: ${available_memory_gb}GB"
    
    if [ "$available_memory_gb" -lt 8 ]; then
        log_verbose "Low memory detected. Consider reducing parallel jobs for stability"
    fi
    
    # Check Xcode command line tools
    if ! xcode-select -p &> /dev/null; then
        log_error "Xcode command line tools not found"
        log_error "Install with: xcode-select --install"
        exit 1
    fi
    
    local xcode_path=$(xcode-select -p)
    log_verbose "Xcode command line tools: $xcode_path"
    
    # Check for required build tools
    local required_tools=("cmake" "git" "pkg-config")
    for tool in "${required_tools[@]}"; do
        if ! command -v "$tool" &> /dev/null; then
            log_error "Required tool not found: $tool"
            log_error "Run setup script first: ./Scripts/setup_macos.sh"
            exit 1
        fi
        
        local tool_version=""
        case "$tool" in
            "cmake")
                tool_version=$(cmake --version | head -n1 | awk '{print $3}')
                ;;
            "git")
                tool_version=$(git --version | awk '{print $3}')
                ;;
            "pkg-config")
                tool_version=$(pkg-config --version)
                ;;
        esac
        
        log_verbose "$tool version: $tool_version"
    done
}

# Architecture configuration
configure_architecture() {
    log_info "Configuring architecture settings..."
    
    local cmake_architectures=""
    
    case "$architecture" in
        "x86_64")
            cmake_architectures="x86_64"
            ;;
        "arm64")
            cmake_architectures="arm64"
            ;;
        "universal")
            cmake_architectures="x86_64;arm64"
            ;;
    esac
    
    log_verbose "CMake architectures: $cmake_architectures"
    echo "$cmake_architectures"
}

# Dependency path discovery
discover_dependency_paths() {
    log_info "Discovering dependency paths..."
    
    local deps_info=""
    
    # Check for Homebrew
    if command -v brew &> /dev/null; then
        local brew_prefix=$(brew --prefix)
        log_verbose "Homebrew prefix: $brew_prefix"
        
        # OpenCV
        if brew list opencv &> /dev/null; then
            local opencv_path=$(brew --prefix opencv)
            deps_info="${deps_info}OPENCV_PATH=${opencv_path}\n"
            log_verbose "OpenCV found: $opencv_path"
        else
            log_error "OpenCV not found via Homebrew. Run setup script first."
            exit 1
        fi
        
        # Qt5
        if brew list qt@5 &> /dev/null; then
            local qt5_path=$(brew --prefix qt@5)
            deps_info="${deps_info}QT5_PATH=${qt5_path}\n"
            log_verbose "Qt5 found: $qt5_path"
        else
            log_error "Qt5 not found via Homebrew. Run setup script first."
            exit 1
        fi
        
        # Eigen
        if brew list eigen &> /dev/null; then
            local eigen_path=$(brew --prefix eigen)
            deps_info="${deps_info}EIGEN_PATH=${eigen_path}\n"
            log_verbose "Eigen found: $eigen_path"
        else
            log_error "Eigen not found via Homebrew. Run setup script first."
            exit 1
        fi
    else
        log_error "Homebrew not found. Install Homebrew and run setup script first."
        exit 1
    fi
    
    # Check for OBS Studio
    local scripts_path=$(cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd)
    local obs_path="${scripts_path}/../Dependencies/obs-studio"
    
    if [ -d "$obs_path/build/install" ]; then
        deps_info="${deps_info}OBS_PATH=${obs_path}/build/install\n"
        log_verbose "OBS Studio found: $obs_path/build/install"
    else
        if [ "$build_plugin" = true ]; then
            log_error "OBS Studio not found. Run setup script first to build OBS Studio."
            exit 1
        else
            log_verbose "OBS Studio not found, but plugin build not requested"
        fi
    fi
    
    echo -e "$deps_info"
}

# CMake configuration generation
generate_cmake_config() {
    local deps_info="$1"
    local cmake_architectures="$2"
    
    log_info "Generating CMake configuration..."
    
    # Extract dependency paths
    local opencv_path=$(echo -e "$deps_info" | grep "OPENCV_PATH=" | cut -d= -f2)
    local qt5_path=$(echo -e "$deps_info" | grep "QT5_PATH=" | cut -d= -f2)
    local eigen_path=$(echo -e "$deps_info" | grep "EIGEN_PATH=" | cut -d= -f2)
    local obs_path=$(echo -e "$deps_info" | grep "OBS_PATH=" | cut -d= -f2)
    
    # Build CMake arguments array
    local cmake_args=(
        "-DCMAKE_BUILD_TYPE=$config"
        "-DCMAKE_OSX_DEPLOYMENT_TARGET=$macos_version"
        "-DCMAKE_OSX_ARCHITECTURES=$cmake_architectures"
        "-DMACOS_BUILD=ON"
    )
    
    # Add dependency paths
    if [ -n "$opencv_path" ]; then
        cmake_args+=("-DOpenCV_DIR=$opencv_path/lib/cmake/opencv4")
    fi
    
    if [ -n "$qt5_path" ]; then
        cmake_args+=("-DQt5_DIR=$qt5_path/lib/cmake/Qt5")
    fi
    
    if [ -n "$eigen_path" ]; then
        cmake_args+=("-DEigen3_DIR=$eigen_path/share/eigen3/cmake")
    fi
    
    if [ -n "$obs_path" ] && [ "$build_plugin" = true ]; then
        cmake_args+=("-DOBS_BUILD_PATH=$obs_path")
    fi
    
    # Add component build options
    cmake_args+=("-DBUILD_OBS_PLUGIN=$build_plugin")
    cmake_args+=("-DBUILD_VIDEO_EDITOR=$build_editor")
    cmake_args+=("-DOBS_PLUGIN_AUTO_INSTALL=$install_plugin")
    cmake_args+=("-DENABLE_TESTING=$enable_testing")
    
    # Add optimization flags based on configuration
    case "$config" in
        "Release")
            cmake_args+=("-DCMAKE_INTERPROCEDURAL_OPTIMIZATION=TRUE")
            cmake_args+=("-DCMAKE_CXX_FLAGS_RELEASE=-O3 -DNDEBUG -fstack-protector-strong")
            ;;
        "Debug")
            cmake_args+=("-DCMAKE_CXX_FLAGS_DEBUG=-g -O0 -fsanitize=address -fno-omit-frame-pointer")
            ;;
        "RelWithDebInfo")
            cmake_args+=("-DCMAKE_CXX_FLAGS_RELWITHDEBINFO=-O2 -g -DNDEBUG")
            ;;
    esac
    
    # Add code signing preparation
    if [ "$enable_code_signing" = true ]; then
        cmake_args+=("-DENABLE_CODE_SIGNING_PREP=ON")
        cmake_args+=("-DCMAKE_XCODE_ATTRIBUTE_CODE_SIGN_IDENTITY=Developer ID Application")
        cmake_args+=("-DCMAKE_XCODE_ATTRIBUTE_ENABLE_HARDENED_RUNTIME=YES")
    fi
    
    # Add installation prefix
    if [ -n "$install_prefix" ]; then
        cmake_args+=("-DCMAKE_INSTALL_PREFIX=$install_prefix")
    fi
    
    # Add verbose output if requested
    if [ "$verbose" = true ]; then
        cmake_args+=("-DCMAKE_VERBOSE_MAKEFILE=ON")
    fi
    
    # Output the configuration
    log_verbose "CMake configuration:"
    for arg in "${cmake_args[@]}"; do
        log_verbose "  $arg"
    done
    
    # Return the arguments as a string
    printf '%s\n' "${cmake_args[@]}"
}

# Build process execution
execute_build() {
    local cmake_args=("$@")
    
    log_info "Starting build process..."
    
    # Get project paths
    local scripts_path=$(cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd)
    local project_path="${scripts_path}/.."
    local build_path="${project_path}/build"
    
    # Handle clean build
    if [ "$clean_build" = true ] && [ -d "$build_path" ]; then
        log_info "Cleaning existing build directory..."
        rm -rf "$build_path"
    fi
    
    # Create build directory
    if [ ! -d "$build_path" ]; then
        log_info "Creating build directory..."
        mkdir -p "$build_path"
    fi
    
    cd "$build_path"
    
    # Run CMake configuration
    log_info "Configuring with CMake..."
    local cmake_start_time=$(date +%s)
    
    if [ "$verbose" = true ]; then
        cmake "${cmake_args[@]}" "$project_path"
    else
        cmake "${cmake_args[@]}" "$project_path" > cmake_config.log 2>&1
        if [ $? -ne 0 ]; then
            log_error "CMake configuration failed. Check cmake_config.log for details."
            tail -20 cmake_config.log
            exit 1
        fi
    fi
    
    local cmake_end_time=$(date +%s)
    local cmake_duration=$((cmake_end_time - cmake_start_time))
    log_verbose "CMake configuration completed in ${cmake_duration}s"
    
    # Run build
    log_info "Building with $parallel_jobs parallel jobs..."
    local build_start_time=$(date +%s)
    
    if [ "$verbose" = true ]; then
        cmake --build . --config "$config" --parallel "$parallel_jobs"
    else
        cmake --build . --config "$config" --parallel "$parallel_jobs" > build.log 2>&1
        if [ $? -ne 0 ]; then
            log_error "Build failed. Check build.log for details."
            tail -20 build.log
            exit 1
        fi
    fi
    
    local build_end_time=$(date +%s)
    local build_duration=$((build_end_time - build_start_time))
    log_success "Build completed in ${build_duration}s"
    
    # Run installation
    log_info "Installing to build directory..."
    local install_start_time=$(date +%s)
    
    if [ "$verbose" = true ]; then
        cmake --install . --config "$config"
    else
        cmake --install . --config "$config" > install.log 2>&1
        if [ $? -ne 0 ]; then
            log_error "Installation failed. Check install.log for details."
            tail -20 install.log
            exit 1
        fi
    fi
    
    local install_end_time=$(date +%s)
    local install_duration=$((install_end_time - install_start_time))
    log_verbose "Installation completed in ${install_duration}s"
    
    # Calculate total time
    local total_duration=$((cmake_duration + build_duration + install_duration))
    log_success "Total build time: ${total_duration}s"
}

# Post-build validation
validate_build_output() {
    log_info "Validating build output..."
    
    local scripts_path=$(cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd)
    local project_path="${scripts_path}/.."
    local build_path="${project_path}/build"
    local install_path="${build_path}/Install"
    
    # Check for core library
    local core_lib_found=false
    local lib_extensions=("dylib" "a")
    
    for ext in "${lib_extensions[@]}"; do
        if find "$install_path" -name "*OpenVisionKit*.$ext" -o -name "*lvk*.$ext" | grep -q .; then
            core_lib_found=true
            break
        fi
    done
    
    if [ "$core_lib_found" = true ]; then
        log_success "Core library found in installation"
    else
        log_error "Core library not found in installation"
        return 1
    fi
    
    # Check for OBS plugin if requested
    if [ "$build_plugin" = true ]; then
        if find "$install_path" -name "*.dylib" | grep -i obs | grep -q .; then
            log_success "OBS plugin found in installation"
        else
            log_error "OBS plugin not found in installation"
            return 1
        fi
    fi
    
    # Check for video editor if requested
    if [ "$build_editor" = true ]; then
        if find "$install_path" -name "*editor*" -o -name "*lvk-editor*" | grep -q .; then
            log_success "Video editor found in installation"
        else
            log_error "Video editor not found in installation"
            return 1
        fi
    fi
    
    # Check architecture of built binaries
    log_info "Verifying binary architectures..."
    local binary_files=$(find "$install_path" -type f \( -name "*.dylib" -o -perm +111 \) | head -5)
    
    for binary in $binary_files; do
        if [ -f "$binary" ]; then
            local archs=$(lipo -archs "$binary" 2>/dev/null || echo "unknown")
            log_verbose "$(basename "$binary"): $archs"
            
            # Verify expected architecture
            case "$architecture" in
                "x86_64")
                    if [[ "$archs" != *"x86_64"* ]]; then
                        log_error "Expected x86_64 architecture not found in $binary"
                        return 1
                    fi
                    ;;
                "arm64")
                    if [[ "$archs" != *"arm64"* ]]; then
                        log_error "Expected arm64 architecture not found in $binary"
                        return 1
                    fi
                    ;;
                "universal")
                    if [[ "$archs" != *"x86_64"* ]] || [[ "$archs" != *"arm64"* ]]; then
                        log_error "Expected universal binary (x86_64 + arm64) not found in $binary"
                        return 1
                    fi
                    ;;
            esac
        fi
    done
    
    log_success "Binary architecture validation passed"
    return 0
}

# Run tests if enabled
run_tests() {
    if [ "$enable_testing" = true ]; then
        log_info "Running tests..."
        
        local scripts_path=$(cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd)
        local project_path="${scripts_path}/.."
        local build_path="${project_path}/build"
        
        cd "$build_path"
        
        if [ "$verbose" = true ]; then
            ctest --output-on-failure --parallel "$parallel_jobs"
        else
            ctest --output-on-failure --parallel "$parallel_jobs" > test.log 2>&1
            if [ $? -ne 0 ]; then
                log_error "Tests failed. Check test.log for details."
                tail -20 test.log
                return 1
            fi
        fi
        
        log_success "All tests passed"
    fi
    
    return 0
}

# Create macOS bundle structure
create_macos_bundle() {
    local install_path="$1"
    local bundle_path="$2"
    
    log_info "Creating macOS bundle structure..."
    
    # Create bundle directory structure
    mkdir -p "$bundle_path/Contents/MacOS"
    mkdir -p "$bundle_path/Contents/Resources"
    mkdir -p "$bundle_path/Contents/Frameworks"
    mkdir -p "$bundle_path/Contents/PlugIns"
    
    # Copy main executable
    if [ -d "$install_path/Binaries" ]; then
        local main_executable=$(find "$install_path/Binaries" -type f -perm +111 | head -1)
        if [ -n "$main_executable" ]; then
            cp "$main_executable" "$bundle_path/Contents/MacOS/"
            log_verbose "Copied main executable: $(basename "$main_executable")"
        fi
    fi
    
    # Copy libraries to Frameworks
    if [ -d "$install_path" ]; then
        find "$install_path" -name "*.dylib" -exec cp {} "$bundle_path/Contents/Frameworks/" \;
        log_verbose "Copied dynamic libraries to Frameworks"
    fi
    
    # Copy OBS plugin if built
    if [ "$build_plugin" = true ] && [ -d "$install_path" ]; then
        local obs_plugin=$(find "$install_path" -name "*obs*" -name "*.dylib" | head -1)
        if [ -n "$obs_plugin" ]; then
            cp "$obs_plugin" "$bundle_path/Contents/PlugIns/"
            log_verbose "Copied OBS plugin to PlugIns"
        fi
    fi
    
    # Create Info.plist
    create_info_plist "$bundle_path/Contents/Info.plist"
    
    # Copy resources
    local scripts_path=$(cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd)
    local assets_path="${scripts_path}/../Assets"
    
    if [ -d "$assets_path" ]; then
        cp "$assets_path"/*.png "$bundle_path/Contents/Resources/" 2>/dev/null || true
        log_verbose "Copied asset files to Resources"
    fi
    
    log_success "macOS bundle created: $bundle_path"
}

# Create Info.plist for macOS bundle
create_info_plist() {
    local plist_path="$1"
    
    log_verbose "Creating Info.plist..."
    
    # Get version information
    local version="1.0.0"
    local build_number=$(date +%Y%m%d%H%M)
    
    cat > "$plist_path" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleExecutable</key>
    <string>OpenVisionKit</string>
    <key>CFBundleIdentifier</key>
    <string>org.openvisionkit.OpenVisionKit</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>OpenVisionKit</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>$version</string>
    <key>CFBundleVersion</key>
    <string>$build_number</string>
    <key>LSMinimumSystemVersion</key>
    <string>$macos_version</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSCameraUsageDescription</key>
    <string>OpenVisionKit needs camera access for video processing.</string>
    <key>NSMicrophoneUsageDescription</key>
    <string>OpenVisionKit needs microphone access for audio processing.</string>
    <key>LSApplicationCategoryType</key>
    <string>public.app-category.video</string>
    <key>CFBundleDocumentTypes</key>
    <array>
        <dict>
            <key>CFBundleTypeExtensions</key>
            <array>
                <string>mp4</string>
                <string>mov</string>
                <string>avi</string>
                <string>mkv</string>
            </array>
            <key>CFBundleTypeName</key>
            <string>Video File</string>
            <key>CFBundleTypeRole</key>
            <string>Editor</string>
            <key>LSTypeIsPackage</key>
            <false/>
        </dict>
    </array>
</dict>
</plist>
EOF
    
    log_verbose "Info.plist created successfully"
}

# Code signing preparation
prepare_code_signing() {
    local bundle_path="$1"
    
    if [ "$enable_code_signing" = false ]; then
        log_verbose "Code signing preparation skipped"
        return 0
    fi
    
    log_info "Preparing for code signing..."
    
    # Create entitlements file
    local entitlements_path="${bundle_path}/Contents/entitlements.plist"
    
    cat > "$entitlements_path" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.security.cs.allow-jit</key>
    <true/>
    <key>com.apple.security.cs.allow-unsigned-executable-memory</key>
    <true/>
    <key>com.apple.security.cs.disable-library-validation</key>
    <true/>
    <key>com.apple.security.device.camera</key>
    <true/>
    <key>com.apple.security.device.microphone</key>
    <true/>
    <key>com.apple.security.files.user-selected.read-write</key>
    <true/>
    <key>com.apple.security.network.client</key>
    <true/>
</dict>
</plist>
EOF
    
    # Set executable permissions
    find "$bundle_path/Contents/MacOS" -type f -exec chmod +x {} \;
    find "$bundle_path/Contents/Frameworks" -name "*.dylib" -exec chmod +x {} \;
    find "$bundle_path/Contents/PlugIns" -name "*.dylib" -exec chmod +x {} \;
    
    log_info "Code signing preparation completed"
    log_info "To sign the bundle, run:"
    log_info "  codesign --deep --force --verify --verbose --sign \"Developer ID Application: Your Name\" \"$bundle_path\""
    log_info "  codesign --verify --deep --strict --verbose=2 \"$bundle_path\""
}

# Create DMG package
create_dmg_package() {
    local bundle_path="$1"
    local package_name="$2"
    local output_path="$3"
    
    log_info "Creating DMG package..."
    
    local temp_dmg="${output_path}/${package_name}_temp.dmg"
    local final_dmg="${output_path}/${package_name}.dmg"
    
    # Remove existing DMG files
    rm -f "$temp_dmg" "$final_dmg"
    
    # Create temporary DMG
    local bundle_size=$(du -sm "$bundle_path" | cut -f1)
    local dmg_size=$((bundle_size + 50)) # Add 50MB padding
    
    hdiutil create -srcfolder "$bundle_path" -volname "$package_name" -fs HFS+ \
            -fsargs "-c c=64,a=16,e=16" -format UDRW -size "${dmg_size}m" "$temp_dmg"
    
    if [ $? -ne 0 ]; then
        log_error "Failed to create temporary DMG"
        return 1
    fi
    
    # Mount the DMG
    local mount_point=$(hdiutil attach -readwrite -noverify -noautoopen "$temp_dmg" | \
                       egrep '^/dev/' | sed 1q | awk '{print $3}')
    
    if [ -z "$mount_point" ]; then
        log_error "Failed to mount temporary DMG"
        return 1
    fi
    
    # Create Applications symlink
    ln -sf /Applications "$mount_point/Applications"
    
    # Set DMG appearance (if osascript is available)
    if command -v osascript &> /dev/null; then
        osascript << EOF
tell application "Finder"
    tell disk "$package_name"
        open
        set current view of container window to icon view
        set toolbar visible of container window to false
        set statusbar visible of container window to false
        set the bounds of container window to {400, 100, 900, 400}
        set theViewOptions to the icon view options of container window
        set arrangement of theViewOptions to not arranged
        set icon size of theViewOptions to 128
        set position of item "$(basename "$bundle_path")" of container window to {150, 150}
        set position of item "Applications" of container window to {350, 150}
        update without registering applications
        delay 2
        close
    end tell
end tell
EOF
    fi
    
    # Unmount the DMG
    hdiutil detach "$mount_point"
    
    # Convert to compressed DMG
    hdiutil convert "$temp_dmg" -format UDZO -imagekey zlib-level=9 -o "$final_dmg"
    
    if [ $? -eq 0 ]; then
        rm -f "$temp_dmg"
        log_success "DMG package created: $final_dmg"
        return 0
    else
        log_error "Failed to create final DMG"
        return 1
    fi
}

# Create PKG package
create_pkg_package() {
    local bundle_path="$1"
    local package_name="$2"
    local output_path="$3"
    
    log_info "Creating PKG package..."
    
    local pkg_path="${output_path}/${package_name}.pkg"
    local temp_dir="${output_path}/pkg_temp"
    
    # Create temporary directory structure
    mkdir -p "$temp_dir/Applications"
    cp -R "$bundle_path" "$temp_dir/Applications/"
    
    # Create package
    pkgbuild --root "$temp_dir" \
             --identifier "org.openvisionkit.OpenVisionKit" \
             --version "1.0.0" \
             --install-location "/" \
             "$pkg_path"
    
    if [ $? -eq 0 ]; then
        rm -rf "$temp_dir"
        log_success "PKG package created: $pkg_path"
        return 0
    else
        log_error "Failed to create PKG package"
        rm -rf "$temp_dir"
        return 1
    fi
}

# Create ZIP package
create_zip_package() {
    local bundle_path="$1"
    local package_name="$2"
    local output_path="$3"
    
    log_info "Creating ZIP package..."
    
    local zip_path="${output_path}/${package_name}.zip"
    local bundle_name=$(basename "$bundle_path")
    
    # Create ZIP file
    local bundle_dir=$(dirname "$bundle_path")
    
    if [ "$verbose" = true ]; then
        (cd "$bundle_dir" && zip -r "$zip_path" "$bundle_name")
    else
        (cd "$bundle_dir" && zip -r "$zip_path" "$bundle_name" > /dev/null)
    fi
    
    if [ $? -eq 0 ]; then
        log_success "ZIP package created: $zip_path"
        return 0
    else
        log_error "Failed to create ZIP package"
        return 1
    fi
}

# Main packaging function
create_distribution_package() {
    if [ "$create_package" = false ]; then
        log_verbose "Package creation skipped"
        return 0
    fi
    
    log_info "Creating distribution package..."
    
    local scripts_path=$(cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd)
    local project_path="${scripts_path}/.."
    local build_path="${project_path}/build"
    local install_path="${build_path}/Install"
    
    # Generate package name if not provided
    if [ -z "$package_name" ]; then
        local version="1.0.0"
        local arch_suffix=""
        
        case "$architecture" in
            "x86_64")
                arch_suffix="-intel"
                ;;
            "arm64")
                arch_suffix="-apple-silicon"
                ;;
            "universal")
                arch_suffix="-universal"
                ;;
        esac
        
        package_name="OpenVisionKit-${version}${arch_suffix}-macOS-${macos_version}"
    fi
    
    # Create bundle structure
    local bundle_path="${build_path}/${package_name}.app"
    create_macos_bundle "$install_path" "$bundle_path"
    
    # Prepare code signing
    prepare_code_signing "$bundle_path"
    
    # Validate bundle
    if ! validate_bundle_structure "$bundle_path"; then
        log_error "Bundle validation failed"
        return 1
    fi
    
    # Create package based on format
    local packages_dir="${build_path}/Packages"
    mkdir -p "$packages_dir"
    
    case "$package_format" in
        "dmg")
            create_dmg_package "$bundle_path" "$package_name" "$packages_dir"
            ;;
        "pkg")
            create_pkg_package "$bundle_path" "$package_name" "$packages_dir"
            ;;
        "zip")
            create_zip_package "$bundle_path" "$package_name" "$packages_dir"
            ;;
        *)
            log_error "Unsupported package format: $package_format"
            return 1
            ;;
    esac
    
    return $?
}

# Validate bundle structure
validate_bundle_structure() {
    local bundle_path="$1"
    
    log_info "Validating bundle structure..."
    
    # Check required directories
    local required_dirs=("Contents" "Contents/MacOS" "Contents/Resources")
    for dir in "${required_dirs[@]}"; do
        if [ ! -d "$bundle_path/$dir" ]; then
            log_error "Missing required directory: $dir"
            return 1
        fi
    done
    
    # Check Info.plist
    if [ ! -f "$bundle_path/Contents/Info.plist" ]; then
        log_error "Missing Info.plist"
        return 1
    fi
    
    # Validate Info.plist
    if command -v plutil &> /dev/null; then
        if ! plutil -lint "$bundle_path/Contents/Info.plist" > /dev/null 2>&1; then
            log_error "Invalid Info.plist format"
            return 1
        fi
    fi
    
    # Check for executable
    if [ ! -d "$bundle_path/Contents/MacOS" ] || [ -z "$(ls -A "$bundle_path/Contents/MacOS")" ]; then
        log_verbose "No executable found in MacOS directory (library-only bundle)"
    fi
    
    # Check architectures of binaries
    local binary_files=$(find "$bundle_path" -type f \( -name "*.dylib" -o -perm +111 \) | head -5)
    
    for binary in $binary_files; do
        if [ -f "$binary" ]; then
            local archs=$(lipo -archs "$binary" 2>/dev/null || echo "unknown")
            log_verbose "$(basename "$binary"): $archs"
            
            # Verify expected architecture
            case "$architecture" in
                "x86_64")
                    if [[ "$archs" != *"x86_64"* ]]; then
                        log_error "Expected x86_64 architecture not found in $binary"
                        return 1
                    fi
                    ;;
                "arm64")
                    if [[ "$archs" != *"arm64"* ]]; then
                        log_error "Expected arm64 architecture not found in $binary"
                        return 1
                    fi
                    ;;
                "universal")
                    if [[ "$archs" != *"x86_64"* ]] || [[ "$archs" != *"arm64"* ]]; then
                        log_error "Expected universal binary (x86_64 + arm64) not found in $binary"
                        return 1
                    fi
                    ;;
            esac
        fi
    done
    
    log_success "Bundle structure validation passed"
    return 0
}

# Generate build report
generate_build_report() {
    log_info "Generating build report..."
    
    local scripts_path=$(cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd)
    local project_path="${scripts_path}/.."
    local build_path="${project_path}/build"
    local report_file="${build_path}/build_report.txt"
    
    cat > "$report_file" << EOF
# OpenVisionKit macOS Build Report
# Generated on: $(date)
# Build script version: 1.0

## Build Configuration
- Configuration: $config
- Architecture: $architecture
- macOS Version: $macos_version
- Parallel Jobs: $parallel_jobs
- Code Signing: $enable_code_signing

## Components Built
- OBS Plugin: $build_plugin
- Video Editor: $build_editor
- Testing: $enable_testing

## System Information
- macOS Version: $(sw_vers -productVersion)
- System Architecture: $(uname -m)
- Available Memory: $(($(sysctl -n hw.memsize) / 1024 / 1024 / 1024))GB
- CPU Cores: $(sysctl -n hw.ncpu)

## Tool Versions
- CMake: $(cmake --version | head -n1 | awk '{print $3}')
- Git: $(git --version | awk '{print $3}')
- Xcode: $(xcode-select -p)

## Build Output
EOF
    
    # Add file listing
    if [ -d "${build_path}/Install" ]; then
        echo "## Installation Contents" >> "$report_file"
        find "${build_path}/Install" -type f | sort >> "$report_file"
    fi
    
    log_info "Build report saved to: $report_file"
}

# Main build function
main() {
    log_info "=== OpenVisionKit macOS Build Script ==="
    log_info "Configuration: $config | Architecture: $architecture | macOS: $macos_version"
    
    # Validate configuration
    validate_configuration
    
    # Detect system capabilities
    detect_system_capabilities
    
    # Configure architecture
    local cmake_architectures=$(configure_architecture)
    
    # Discover dependency paths
    local deps_info=$(discover_dependency_paths)
    
    # Generate CMake configuration
    local cmake_config=$(generate_cmake_config "$deps_info" "$cmake_architectures")
    
    # Convert to array for execution
    local cmake_args=()
    while IFS= read -r line; do
        cmake_args+=("$line")
    done <<< "$cmake_config"
    
    # Execute build
    execute_build "${cmake_args[@]}"
    
    # Validate build output
    if ! validate_build_output; then
        log_error "Build validation failed"
        exit 1
    fi
    
    # Run tests if enabled
    if ! run_tests; then
        log_error "Tests failed"
        exit 1
    fi
    
    # Create distribution package if requested
    if ! create_distribution_package; then
        log_error "Package creation failed"
        exit 1
    fi
    
    # Generate build report
    generate_build_report
    
    log_success "=== Build Complete ==="
    log_info ""
    log_info "Build artifacts are available in:"
    log_info "  $(cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd)/../build/Install/"
    log_info ""
    
    if [ "$build_plugin" = true ]; then
        log_info "OBS Plugin built successfully"
        if [ "$install_plugin" = true ]; then
            log_info "Plugin has been installed to OBS Studio"
        else
            log_info "To install the plugin manually, copy it to:"
            log_info "  ~/Library/Application Support/obs-studio/plugins/"
        fi
    fi
    
    if [ "$build_editor" = true ]; then
        log_info "Video Editor built successfully"
        log_info "Run with: ./build/Install/Binaries/lvk-editor"
    fi
    
    if [ "$enable_testing" = true ]; then
        log_info "All tests passed successfully"
    fi
    
    if [ "$create_package" = true ]; then
        log_info "Distribution package created successfully"
        log_info "Package location: $(cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd)/../build/Packages/"
        log_info "Package format: $package_format"
    fi
}

# Execute main function with all arguments
main "$@"