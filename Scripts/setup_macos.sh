#!/bin/bash

# OpenVisionKit macOS Setup Script
# Automated dependency installation and configuration for macOS

set -e  # Exit on any error

# Parse arguments
config="Release"
force_reinstall=false
verbose=false

while getopts "c:fv" args; do
    case $args in
        c)
            config=${OPTARG}
            ;;
        f)
            force_reinstall=true
            ;;
        v)
            verbose=true
            ;;
        *)
            echo "Usage: $0 [-c config] [-f] [-v]"
            echo "  -c config: Build configuration (Release/Debug, default: Release)"
            echo "  -f: Force reinstall of dependencies"
            echo "  -v: Verbose output"
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

# Create main paths
scripts_path=$(cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd)
deps_path="${scripts_path}/../Dependencies"

log_info "Starting OpenVisionKit macOS setup..."
log_info "Configuration: $config"
log_info "Dependencies path: $deps_path"

# Create dependencies directory
if [ ! -d "$deps_path" ]; then
    log_info "Creating dependencies directory..."
    mkdir -p "$deps_path"
fi

# Function to check if Homebrew is installed
check_homebrew() {
    if ! command -v brew &> /dev/null; then
        log_error "Homebrew is not installed. Please install Homebrew first:"
        log_error "  /bin/bash -c \"\$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)\""
        exit 1
    fi
    log_info "Homebrew found: $(brew --version | head -n1)"
}

# Function to check if a package is installed via Homebrew
is_package_installed() {
    local package=$1
    brew list "$package" &> /dev/null
}

# Function to get package version
get_package_version() {
    local package=$1
    if is_package_installed "$package"; then
        brew list --versions "$package" | head -n1 | awk '{print $2}'
    else
        echo "not_installed"
    fi
}

# Function to install or update a Homebrew package
install_or_update_package() {
    local package=$1
    local required_version=$2
    
    if is_package_installed "$package"; then
        local current_version=$(get_package_version "$package")
        log_info "$package is already installed (version: $current_version)"
        
        if [ "$force_reinstall" = true ]; then
            log_info "Force reinstall requested, reinstalling $package..."
            brew reinstall "$package"
        else
            log_verbose "Skipping $package installation (use -f to force reinstall)"
        fi
    else
        log_info "Installing $package..."
        brew install "$package"
    fi
    
    # Verify installation
    if is_package_installed "$package"; then
        local installed_version=$(get_package_version "$package")
        log_info "$package successfully installed/updated (version: $installed_version)"
    else
        log_error "Failed to install $package"
        exit 1
    fi
}

# Function to validate dependency versions
validate_dependency_versions() {
    log_info "Validating dependency versions..."
    
    # Check CMake version (minimum 3.16)
    if command -v cmake &> /dev/null; then
        local cmake_version=$(cmake --version | head -n1 | awk '{print $3}')
        log_info "CMake version: $cmake_version"
        
        # Simple version check (assumes semantic versioning)
        local major=$(echo "$cmake_version" | cut -d. -f1)
        local minor=$(echo "$cmake_version" | cut -d. -f2)
        
        if [ "$major" -lt 3 ] || ([ "$major" -eq 3 ] && [ "$minor" -lt 16 ]); then
            log_error "CMake version $cmake_version is too old. Minimum required: 3.16"
            exit 1
        fi
    else
        log_error "CMake not found after installation"
        exit 1
    fi
    
    # Check OpenCV
    if is_package_installed "opencv"; then
        local opencv_version=$(get_package_version "opencv")
        log_info "OpenCV version: $opencv_version"
    fi
    
    # Check Qt5
    if is_package_installed "qt@5"; then
        local qt5_version=$(get_package_version "qt@5")
        log_info "Qt5 version: $qt5_version"
    fi
    
    # Check Eigen
    if is_package_installed "eigen"; then
        local eigen_version=$(get_package_version "eigen")
        log_info "Eigen version: $eigen_version"
    fi
    
    # Check pkg-config
    if command -v pkg-config &> /dev/null; then
        local pkgconfig_version=$(pkg-config --version)
        log_info "pkg-config version: $pkgconfig_version"
    fi
}

# Function to build OBS Studio for macOS
build_obs_studio() {
    log_info "Building OBS Studio for macOS..."
    
    local obs_version="30.0.2"  # Use a recent stable version
    local obs_path="${deps_path}/obs-studio"
    
    # Clone OBS Studio if not already present
    if [ ! -d "$obs_path" ]; then
        log_info "Cloning OBS Studio version $obs_version..."
        cd "$deps_path"
        git clone -b "$obs_version" --recursive https://github.com/obsproject/obs-studio.git
        
        if [ ! -d "$obs_path" ]; then
            log_error "Failed to clone OBS Studio"
            exit 1
        fi
    else
        log_info "OBS Studio already cloned"
        if [ "$force_reinstall" = true ]; then
            log_info "Force reinstall requested, removing existing OBS Studio..."
            rm -rf "$obs_path"
            cd "$deps_path"
            git clone -b "$obs_version" --recursive https://github.com/obsproject/obs-studio.git
        fi
    fi
    
    # Install OBS Studio build dependencies via Homebrew
    log_info "Installing OBS Studio build dependencies..."
    local obs_deps=(
        "ffmpeg"
        "x264"
        "mbedtls"
        "jansson"
        "librist"
        "popt"
        "rnnoise"
        "speexdsp"
        "jack"
        "vlc"
        "swig"
        "python@3.11"
    )
    
    for dep in "${obs_deps[@]}"; do
        install_or_update_package "$dep"
    done
    
    # Create build directory
    local obs_build_path="${obs_path}/build"
    if [ -d "$obs_build_path" ] && [ "$force_reinstall" = true ]; then
        log_info "Removing existing OBS build directory..."
        rm -rf "$obs_build_path"
    fi
    
    if [ ! -d "$obs_build_path" ]; then
        mkdir -p "$obs_build_path"
    fi
    
    cd "$obs_build_path"
    
    # Configure OBS Studio build for macOS
    log_info "Configuring OBS Studio build..."
    
    # Get Qt5 path for OBS
    local qt5_path=""
    if is_package_installed "qt@5"; then
        qt5_path=$(brew --prefix qt@5)
    fi
    
    # Get FFmpeg path
    local ffmpeg_path=""
    if is_package_installed "ffmpeg"; then
        ffmpeg_path=$(brew --prefix ffmpeg)
    fi
    
    # Configure with CMake
    cmake -DCMAKE_BUILD_TYPE="$config" \
          -DENABLE_BROWSER=OFF \
          -DENABLE_WEBSOCKET=ON \
          -DENABLE_LIBFDK=OFF \
          -DENABLE_SCRIPTING=OFF \
          -DENABLE_PYTHON=OFF \
          -DENABLE_LUA=OFF \
          -DBUILD_TESTS=OFF \
          -DBUILD_FOR_DISTRIBUTION=ON \
          -DCMAKE_OSX_DEPLOYMENT_TARGET=10.15 \
          -DCMAKE_OSX_ARCHITECTURES="x86_64;arm64" \
          ${qt5_path:+-DQt5_DIR="$qt5_path/lib/cmake/Qt5"} \
          ${ffmpeg_path:+-DFFMPEG_ROOT="$ffmpeg_path"} \
          -DCMAKE_PREFIX_PATH="$(brew --prefix)" \
          ..
    
    if [ $? -ne 0 ]; then
        log_error "OBS Studio CMake configuration failed"
        exit 1
    fi
    
    # Build OBS Studio
    log_info "Building OBS Studio (this may take a while)..."
    cmake --build . --config "$config" --parallel $(sysctl -n hw.ncpu)
    
    if [ $? -ne 0 ]; then
        log_error "OBS Studio build failed"
        exit 1
    fi
    
    # Install OBS Studio
    log_info "Installing OBS Studio..."
    cmake --install . --prefix "./install/" --config "$config"
    
    if [ $? -ne 0 ]; then
        log_error "OBS Studio installation failed"
        exit 1
    fi
    
    log_info "OBS Studio built and installed successfully"
    
    # Verify OBS Studio installation
    local obs_executable="${obs_build_path}/install/bin/obs"
    if [ -f "$obs_executable" ]; then
        log_info "OBS Studio executable found: $obs_executable"
    else
        log_error "OBS Studio executable not found after installation"
    fi
    
    # Check for plugin development headers
    local obs_headers="${obs_build_path}/install/include/obs"
    if [ -d "$obs_headers" ]; then
        log_info "OBS Studio plugin development headers found"
    else
        log_error "OBS Studio plugin development headers not found"
    fi
}

# Function to discover dependency in standard macOS locations
discover_dependency_location() {
    local dep_name=$1
    local found_path=""
    local found_method=""
    
    log_verbose "Searching for $dep_name in standard macOS locations..."
    
    # Method 1: Homebrew detection
    if command -v brew &> /dev/null; then
        if is_package_installed "$dep_name"; then
            found_path=$(brew --prefix "$dep_name" 2>/dev/null)
            if [ -n "$found_path" ] && [ -d "$found_path" ]; then
                found_method="homebrew"
                log_verbose "$dep_name found via Homebrew: $found_path"
            fi
        fi
    fi
    
    # Method 2: Framework detection (for macOS frameworks)
    if [ -z "$found_path" ]; then
        local framework_locations=(
            "/Library/Frameworks"
            "/System/Library/Frameworks"
            "~/Library/Frameworks"
        )
        
        for location in "${framework_locations[@]}"; do
            local framework_path="${location}/${dep_name}.framework"
            if [ -d "$framework_path" ]; then
                found_path="$framework_path"
                found_method="framework"
                log_verbose "$dep_name found as framework: $found_path"
                break
            fi
        done
    fi
    
    # Method 3: Standard Unix paths
    if [ -z "$found_path" ]; then
        local standard_locations=(
            "/usr/local"
            "/opt/local"
            "/usr"
        )
        
        for location in "${standard_locations[@]}"; do
            # Check for headers and libraries
            local include_path="${location}/include"
            local lib_path="${location}/lib"
            
            case "$dep_name" in
                "opencv")
                    if [ -d "$include_path/opencv4" ] && [ -f "$lib_path/libopencv_core.dylib" ]; then
                        found_path="$location"
                        found_method="standard"
                        break
                    fi
                    ;;
                "eigen"|"eigen3")
                    if [ -d "$include_path/eigen3" ]; then
                        found_path="$location"
                        found_method="standard"
                        break
                    fi
                    ;;
                "qt5"|"qt@5")
                    if [ -d "$lib_path/cmake/Qt5" ]; then
                        found_path="$location"
                        found_method="standard"
                        break
                    fi
                    ;;
            esac
        done
    fi
    
    # Method 4: pkg-config detection
    if [ -z "$found_path" ] && command -v pkg-config &> /dev/null; then
        local pkg_names=()
        case "$dep_name" in
            "opencv")
                pkg_names=("opencv4" "opencv")
                ;;
            "eigen"|"eigen3")
                pkg_names=("eigen3")
                ;;
            "qt5"|"qt@5")
                pkg_names=("Qt5Core" "qt5")
                ;;
        esac
        
        for pkg_name in "${pkg_names[@]}"; do
            if pkg-config --exists "$pkg_name" 2>/dev/null; then
                local pkg_prefix=$(pkg-config --variable=prefix "$pkg_name" 2>/dev/null)
                if [ -n "$pkg_prefix" ] && [ -d "$pkg_prefix" ]; then
                    found_path="$pkg_prefix"
                    found_method="pkg-config"
                    log_verbose "$dep_name found via pkg-config: $found_path"
                    break
                fi
            fi
        done
    fi
    
    # Output results
    if [ -n "$found_path" ]; then
        echo "$found_path|$found_method"
    else
        echo "|not_found"
    fi
}

# Function to validate dependency installation
validate_dependency_installation() {
    local dep_name=$1
    local dep_path=$2
    local method=$3
    
    log_verbose "Validating $dep_name installation at $dep_path (method: $method)"
    
    case "$dep_name" in
        "opencv")
            # Check for OpenCV headers and libraries
            local opencv_include=""
            local opencv_lib=""
            
            if [ "$method" = "homebrew" ]; then
                opencv_include="$dep_path/include/opencv4"
                opencv_lib="$dep_path/lib"
            elif [ "$method" = "framework" ]; then
                opencv_include="$dep_path/Headers"
                opencv_lib="$dep_path"
            else
                opencv_include="$dep_path/include/opencv4"
                opencv_lib="$dep_path/lib"
            fi
            
            if [ -d "$opencv_include" ] && ([ -f "$opencv_lib/libopencv_core.dylib" ] || [ -f "$opencv_lib/libopencv_core.a" ]); then
                return 0
            fi
            ;;
            
        "qt5"|"qt@5")
            # Check for Qt5 CMake configuration
            local qt5_cmake=""
            
            if [ "$method" = "homebrew" ]; then
                qt5_cmake="$dep_path/lib/cmake/Qt5"
            else
                qt5_cmake="$dep_path/lib/cmake/Qt5"
            fi
            
            if [ -d "$qt5_cmake" ]; then
                return 0
            fi
            ;;
            
        "eigen"|"eigen3")
            # Check for Eigen headers
            local eigen_include=""
            
            if [ "$method" = "homebrew" ]; then
                eigen_include="$dep_path/include/eigen3"
            else
                eigen_include="$dep_path/include/eigen3"
            fi
            
            if [ -d "$eigen_include" ]; then
                return 0
            fi
            ;;
    esac
    
    return 1
}

# Function to create configuration validation report
create_configuration_report() {
    log_info "Creating dependency configuration report..."
    
    local report_file="${deps_path}/macos_dependency_report.txt"
    
    cat > "$report_file" << EOF
# OpenVisionKit macOS Dependency Configuration Report
# Generated on: $(date)
# System: $(uname -a)
# Homebrew: $(brew --version 2>/dev/null || echo "Not installed")

EOF
    
    local dependencies=("opencv" "qt@5" "eigen" "cmake" "pkg-config")
    
    for dep in "${dependencies[@]}"; do
        echo "## $dep" >> "$report_file"
        
        local result=$(discover_dependency_location "$dep")
        local dep_path=$(echo "$result" | cut -d'|' -f1)
        local method=$(echo "$result" | cut -d'|' -f2)
        
        if [ "$method" != "not_found" ]; then
            echo "- Status: Found" >> "$report_file"
            echo "- Path: $dep_path" >> "$report_file"
            echo "- Method: $method" >> "$report_file"
            
            if validate_dependency_installation "$dep" "$dep_path" "$method"; then
                echo "- Validation: PASSED" >> "$report_file"
            else
                echo "- Validation: FAILED" >> "$report_file"
            fi
            
            # Add version information if available
            case "$dep" in
                "cmake")
                    if command -v cmake &> /dev/null; then
                        echo "- Version: $(cmake --version | head -n1 | awk '{print $3}')" >> "$report_file"
                    fi
                    ;;
                *)
                    if is_package_installed "$dep"; then
                        echo "- Version: $(get_package_version "$dep")" >> "$report_file"
                    fi
                    ;;
            esac
        else
            echo "- Status: NOT FOUND" >> "$report_file"
            echo "- Suggested installation: brew install $dep" >> "$report_file"
        fi
        
        echo "" >> "$report_file"
    done
    
    # Add OBS Studio information
    echo "## OBS Studio" >> "$report_file"
    local obs_path="${deps_path}/obs-studio"
    if [ -d "$obs_path/build/install" ]; then
        echo "- Status: Built from source" >> "$report_file"
        echo "- Path: $obs_path/build/install" >> "$report_file"
        echo "- Headers: $obs_path/build/install/include" >> "$report_file"
        echo "- Libraries: $obs_path/build/install/lib" >> "$report_file"
    else
        echo "- Status: NOT BUILT" >> "$report_file"
        echo "- Note: Run setup script to build OBS Studio" >> "$report_file"
    fi
    
    log_info "Configuration report saved to: $report_file"
}

# Function to discover and validate dependency paths
discover_dependency_paths() {
    log_info "Discovering dependency paths with automatic detection..."
    
    # Get Homebrew prefix
    local brew_prefix=""
    if command -v brew &> /dev/null; then
        brew_prefix=$(brew --prefix)
        log_info "Homebrew prefix: $brew_prefix"
    else
        log_info "Homebrew not found, using alternative detection methods"
    fi
    
    # Discover each dependency
    local dependencies=("opencv" "qt@5" "eigen")
    
    for dep in "${dependencies[@]}"; do
        log_info "Discovering $dep..."
        
        local result=$(discover_dependency_location "$dep")
        local dep_path=$(echo "$result" | cut -d'|' -f1)
        local method=$(echo "$result" | cut -d'|' -f2)
        
        if [ "$method" != "not_found" ]; then
            log_info "$dep found via $method: $dep_path"
            
            if validate_dependency_installation "$dep" "$dep_path" "$method"; then
                log_info "$dep installation validated successfully"
            else
                log_error "$dep installation validation failed"
            fi
        else
            log_error "$dep not found in any standard location"
            log_error "Please install $dep using: brew install $dep"
        fi
    done
    
    # Check OBS Studio
    local obs_path="${deps_path}/obs-studio"
    if [ -d "$obs_path" ]; then
        log_info "OBS Studio source found: $obs_path"
        
        local obs_build_path="${obs_path}/build"
        if [ -d "$obs_build_path/install" ]; then
            log_info "OBS Studio installation found: $obs_build_path/install"
            
            # Validate OBS installation
            if [ -d "$obs_build_path/install/include/obs" ] && [ -f "$obs_build_path/install/lib/libobs.dylib" ]; then
                log_info "OBS Studio plugin development environment validated"
            else
                log_error "OBS Studio plugin development files incomplete"
            fi
        else
            log_error "OBS Studio not built. Run setup script to build OBS Studio."
        fi
    else
        log_error "OBS Studio source not found. Run setup script to download and build OBS Studio."
    fi
    
    # Create comprehensive configuration report
    create_configuration_report
}

# Main installation process
main() {
    log_info "=== OpenVisionKit macOS Setup ==="
    
    # Check prerequisites
    check_homebrew
    
    # Update Homebrew
    log_info "Updating Homebrew..."
    brew update
    
    # Install core build tools
    log_info "Installing core build dependencies..."
    install_or_update_package "cmake"
    install_or_update_package "pkg-config"
    install_or_update_package "git"
    
    # Install video processing dependencies
    log_info "Installing video processing dependencies..."
    install_or_update_package "opencv"
    install_or_update_package "qt@5"
    install_or_update_package "eigen"
    
    # Install additional development tools
    log_info "Installing additional development tools..."
    install_or_update_package "ninja"  # Fast build system
    install_or_update_package "ccache" # Compiler cache for faster builds
    
    # Build OBS Studio for plugin development
    log_info "Building OBS Studio for plugin development..."
    build_obs_studio
    
    # Validate installations
    validate_dependency_versions
    
    # Discover and validate paths
    discover_dependency_paths
    
    log_info "=== Setup Complete ==="
    log_info "All dependencies have been installed successfully!"
    log_info ""
    log_info "Next steps:"
    log_info "1. Run the build script: ./Scripts/build_macos.sh"
    log_info "2. Or configure manually with CMake using the discovered paths"
    log_info ""
    log_info "Dependency paths for manual configuration:"
    
    if is_package_installed "opencv"; then
        echo "  OpenCV_DIR=$(brew --prefix opencv)/lib/cmake/opencv4"
    fi
    
    if is_package_installed "qt@5"; then
        echo "  Qt5_DIR=$(brew --prefix qt@5)/lib/cmake/Qt5"
    fi
    
    if is_package_installed "eigen"; then
        echo "  Eigen3_DIR=$(brew --prefix eigen)/share/eigen3/cmake"
    fi
    
    # OBS Studio paths
    local obs_path="${deps_path}/obs-studio"
    if [ -d "$obs_path/build/install" ]; then
        echo "  OBS_STUDIO_DIR=${obs_path}/build/install"
        echo "  OBS_INCLUDE_DIR=${obs_path}/build/install/include"
        echo "  OBS_LIB_DIR=${obs_path}/build/install/lib"
    fi
}

# Run main function
main "$@"