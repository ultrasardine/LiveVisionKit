# FindMacOSDependencies.cmake
# Comprehensive macOS dependency detection for OpenVisionKit
# Handles Homebrew, framework, and manual installation detection

# Include required CMake modules
include(FindPackageHandleStandardArgs)

# Set up macOS-specific variables
set(MACOS_HOMEBREW_PREFIX "")
set(MACOS_DEPENDENCY_PATHS "")

# Function to detect Homebrew installation
function(detect_homebrew)
    execute_process(
        COMMAND which brew
        OUTPUT_VARIABLE BREW_EXECUTABLE
        OUTPUT_STRIP_TRAILING_WHITESPACE
        ERROR_QUIET
    )
    
    if(BREW_EXECUTABLE)
        execute_process(
            COMMAND brew --prefix
            OUTPUT_VARIABLE HOMEBREW_PREFIX
            OUTPUT_STRIP_TRAILING_WHITESPACE
            ERROR_QUIET
        )
        
        if(HOMEBREW_PREFIX)
            set(MACOS_HOMEBREW_PREFIX "${HOMEBREW_PREFIX}" PARENT_SCOPE)
            message(STATUS "Found Homebrew at: ${HOMEBREW_PREFIX}")
        endif()
    endif()
endfunction()

# Function to find OpenCV on macOS
function(find_opencv_macos)
    set(OPENCV_FOUND FALSE PARENT_SCOPE)
    set(OPENCV_DETECTION_METHOD "" PARENT_SCOPE)
    
    # Method 1: Try Homebrew OpenCV
    if(MACOS_HOMEBREW_PREFIX)
        execute_process(
            COMMAND brew --prefix opencv
            OUTPUT_VARIABLE HOMEBREW_OPENCV_PREFIX
            OUTPUT_STRIP_TRAILING_WHITESPACE
            ERROR_QUIET
        )
        
        if(HOMEBREW_OPENCV_PREFIX AND EXISTS "${HOMEBREW_OPENCV_PREFIX}")
            # Try opencv4 first (newer installations)
            set(OPENCV_CMAKE_DIR "${HOMEBREW_OPENCV_PREFIX}/lib/cmake/opencv4")
            if(NOT EXISTS "${OPENCV_CMAKE_DIR}")
                # Fallback to opencv (older installations)
                set(OPENCV_CMAKE_DIR "${HOMEBREW_OPENCV_PREFIX}/lib/cmake/opencv")
            endif()
            
            if(EXISTS "${OPENCV_CMAKE_DIR}")
                set(OpenCV_DIR "${OPENCV_CMAKE_DIR}" PARENT_SCOPE)
                find_package(OpenCV QUIET PATHS "${OPENCV_CMAKE_DIR}" NO_DEFAULT_PATH)
                
                if(OpenCV_FOUND)
                    set(OPENCV_FOUND TRUE PARENT_SCOPE)
                    set(OPENCV_DETECTION_METHOD "Homebrew" PARENT_SCOPE)
                    set(OPENCV_INSTALL_PATH "${HOMEBREW_OPENCV_PREFIX}" PARENT_SCOPE)
                    message(STATUS "Found OpenCV via Homebrew: ${OpenCV_VERSION} at ${HOMEBREW_OPENCV_PREFIX}")
                    return()
                endif()
            endif()
        endif()
    endif()
    
    # Method 2: Try OpenCV.framework in standard macOS locations
    set(FRAMEWORK_SEARCH_PATHS
        "/Library/Frameworks"
        "/System/Library/Frameworks"
        "~/Library/Frameworks"
        "/usr/local/Frameworks"
    )
    
    foreach(FRAMEWORK_PATH ${FRAMEWORK_SEARCH_PATHS})
        if(EXISTS "${FRAMEWORK_PATH}/OpenCV.framework")
            set(OPENCV_FRAMEWORK_PATH "${FRAMEWORK_PATH}/OpenCV.framework")
            
            # Set up framework variables
            set(OpenCV_LIBS "${OPENCV_FRAMEWORK_PATH}" PARENT_SCOPE)
            set(OpenCV_INCLUDE_DIRS "${OPENCV_FRAMEWORK_PATH}/Headers" PARENT_SCOPE)
            
            # Try to determine version from framework
            if(EXISTS "${OPENCV_FRAMEWORK_PATH}/Resources/Info.plist")
                execute_process(
                    COMMAND plutil -extract CFBundleShortVersionString raw "${OPENCV_FRAMEWORK_PATH}/Resources/Info.plist"
                    OUTPUT_VARIABLE OPENCV_FRAMEWORK_VERSION
                    OUTPUT_STRIP_TRAILING_WHITESPACE
                    ERROR_QUIET
                )
                if(OPENCV_FRAMEWORK_VERSION)
                    set(OpenCV_VERSION "${OPENCV_FRAMEWORK_VERSION}" PARENT_SCOPE)
                endif()
            endif()
            
            set(OPENCV_FOUND TRUE PARENT_SCOPE)
            set(OPENCV_DETECTION_METHOD "Framework" PARENT_SCOPE)
            set(OPENCV_INSTALL_PATH "${FRAMEWORK_PATH}" PARENT_SCOPE)
            message(STATUS "Found OpenCV Framework at: ${OPENCV_FRAMEWORK_PATH}")
            return()
        endif()
    endforeach()
    
    # Method 3: Try standard CMake find_package with common paths
    set(OPENCV_SEARCH_PATHS
        "/usr/local"
        "/opt/local"
        "/usr"
    )
    
    foreach(SEARCH_PATH ${OPENCV_SEARCH_PATHS})
        if(EXISTS "${SEARCH_PATH}/lib/cmake/opencv4")
            find_package(OpenCV QUIET PATHS "${SEARCH_PATH}/lib/cmake/opencv4" NO_DEFAULT_PATH)
        elseif(EXISTS "${SEARCH_PATH}/lib/cmake/opencv")
            find_package(OpenCV QUIET PATHS "${SEARCH_PATH}/lib/cmake/opencv" NO_DEFAULT_PATH)
        endif()
        
        if(OpenCV_FOUND)
            set(OPENCV_FOUND TRUE PARENT_SCOPE)
            set(OPENCV_DETECTION_METHOD "Standard Path" PARENT_SCOPE)
            set(OPENCV_INSTALL_PATH "${SEARCH_PATH}" PARENT_SCOPE)
            message(STATUS "Found OpenCV via standard path: ${OpenCV_VERSION} at ${SEARCH_PATH}")
            return()
        endif()
    endforeach()
    
    # Method 4: Fallback to user-specified OPENCV_BUILD_PATH
    if(OPENCV_BUILD_PATH AND EXISTS "${OPENCV_BUILD_PATH}")
        find_package(OpenCV QUIET PATHS "${OPENCV_BUILD_PATH}" NO_DEFAULT_PATH)
        
        if(OpenCV_FOUND)
            set(OPENCV_FOUND TRUE PARENT_SCOPE)
            set(OPENCV_DETECTION_METHOD "User Specified" PARENT_SCOPE)
            set(OPENCV_INSTALL_PATH "${OPENCV_BUILD_PATH}" PARENT_SCOPE)
            message(STATUS "Found OpenCV via user path: ${OpenCV_VERSION} at ${OPENCV_BUILD_PATH}")
            return()
        endif()
    endif()
    
    # If we get here, OpenCV was not found
    message(WARNING "OpenCV not found via any detection method")
endfunction()

# Function to validate OpenCV installation
function(validate_opencv_installation)
    if(NOT OpenCV_FOUND)
        return()
    endif()
    
    # Check for required OpenCV modules
    set(REQUIRED_OPENCV_MODULES core imgproc imgcodecs videoio highgui)
    set(MISSING_MODULES "")
    
    foreach(MODULE ${REQUIRED_OPENCV_MODULES})
        if(NOT TARGET opencv_${MODULE})
            list(APPEND MISSING_MODULES ${MODULE})
        endif()
    endforeach()
    
    if(MISSING_MODULES)
        message(WARNING "OpenCV installation is missing required modules: ${MISSING_MODULES}")
        set(OPENCV_VALID FALSE PARENT_SCOPE)
    else()
        set(OPENCV_VALID TRUE PARENT_SCOPE)
        message(STATUS "OpenCV installation validated successfully")
    endif()
    
    # Check OpenCV version compatibility
    if(OpenCV_VERSION VERSION_LESS "4.0.0")
        message(WARNING "OpenCV version ${OpenCV_VERSION} is older than recommended minimum 4.0.0")
    endif()
endfunction()

# Main function to detect all macOS dependencies
function(detect_macos_dependencies)
    message(STATUS "Detecting macOS dependencies...")
    
    # Detect Homebrew first
    detect_homebrew()
    
    # Detect OpenCV
    find_opencv_macos()
    if(OPENCV_FOUND)
        validate_opencv_installation()
    endif()
    
    # Detect Qt5
    find_qt5_macos()
    if(QT5_FOUND)
        validate_qt5_installation()
    endif()
    
    # Detect Eigen3
    find_eigen3_macos()
    if(EIGEN3_FOUND)
        validate_eigen3_installation()
    endif()
    
    # Export results to parent scope
    set(MACOS_HOMEBREW_PREFIX "${MACOS_HOMEBREW_PREFIX}" PARENT_SCOPE)
    
    # OpenCV results
    set(OPENCV_FOUND "${OPENCV_FOUND}" PARENT_SCOPE)
    set(OPENCV_DETECTION_METHOD "${OPENCV_DETECTION_METHOD}" PARENT_SCOPE)
    set(OPENCV_INSTALL_PATH "${OPENCV_INSTALL_PATH}" PARENT_SCOPE)
    set(OPENCV_VALID "${OPENCV_VALID}" PARENT_SCOPE)
    
    # Qt5 results
    set(QT5_FOUND "${QT5_FOUND}" PARENT_SCOPE)
    set(QT5_DETECTION_METHOD "${QT5_DETECTION_METHOD}" PARENT_SCOPE)
    set(QT5_INSTALL_PATH "${QT5_INSTALL_PATH}" PARENT_SCOPE)
    set(QT5_VALID "${QT5_VALID}" PARENT_SCOPE)
    
    # Eigen3 results
    set(EIGEN3_FOUND "${EIGEN3_FOUND}" PARENT_SCOPE)
    set(EIGEN3_DETECTION_METHOD "${EIGEN3_DETECTION_METHOD}" PARENT_SCOPE)
    set(EIGEN3_INSTALL_PATH "${EIGEN3_INSTALL_PATH}" PARENT_SCOPE)
    set(EIGEN3_VALID "${EIGEN3_VALID}" PARENT_SCOPE)
    
    # Export variables to parent scope for CMake usage
    if(OPENCV_FOUND)
        set(OpenCV_FOUND "${OpenCV_FOUND}" PARENT_SCOPE)
        set(OpenCV_VERSION "${OpenCV_VERSION}" PARENT_SCOPE)
        set(OpenCV_LIBS "${OpenCV_LIBS}" PARENT_SCOPE)
        set(OpenCV_INCLUDE_DIRS "${OpenCV_INCLUDE_DIRS}" PARENT_SCOPE)
    endif()
    
    if(QT5_FOUND)
        set(Qt5_FOUND "${Qt5_FOUND}" PARENT_SCOPE)
        set(Qt5_VERSION "${Qt5_VERSION}" PARENT_SCOPE)
    endif()
    
    if(EIGEN3_FOUND)
        set(Eigen3_FOUND "${Eigen3_FOUND}" PARENT_SCOPE)
        set(Eigen3_VERSION "${Eigen3_VERSION}" PARENT_SCOPE)
        set(Eigen3_INCLUDE_DIRS "${Eigen3_INCLUDE_DIRS}" PARENT_SCOPE)
    endif()
endfunction()

# Function to find Qt5 on macOS
function(find_qt5_macos)
    set(QT5_FOUND FALSE PARENT_SCOPE)
    set(QT5_DETECTION_METHOD "" PARENT_SCOPE)
    
    # Method 1: Try Homebrew Qt5
    if(MACOS_HOMEBREW_PREFIX)
        execute_process(
            COMMAND brew --prefix qt5
            OUTPUT_VARIABLE HOMEBREW_QT5_PREFIX
            OUTPUT_STRIP_TRAILING_WHITESPACE
            ERROR_QUIET
        )
        
        if(HOMEBREW_QT5_PREFIX AND EXISTS "${HOMEBREW_QT5_PREFIX}")
            set(Qt5_DIR "${HOMEBREW_QT5_PREFIX}/lib/cmake/Qt5")
            
            if(EXISTS "${Qt5_DIR}")
                find_package(Qt5 QUIET COMPONENTS Core Gui Widgets Test Concurrent OpenGL PATHS "${Qt5_DIR}" NO_DEFAULT_PATH)
                
                if(Qt5_FOUND)
                    set(QT5_FOUND TRUE PARENT_SCOPE)
                    set(QT5_DETECTION_METHOD "Homebrew" PARENT_SCOPE)
                    set(QT5_INSTALL_PATH "${HOMEBREW_QT5_PREFIX}" PARENT_SCOPE)
                    message(STATUS "Found Qt5 via Homebrew: ${Qt5_VERSION} at ${HOMEBREW_QT5_PREFIX}")
                    return()
                endif()
            endif()
        endif()
        
        # Also try qt@5 (versioned formula)
        execute_process(
            COMMAND brew --prefix qt@5
            OUTPUT_VARIABLE HOMEBREW_QT5_VERSIONED_PREFIX
            OUTPUT_STRIP_TRAILING_WHITESPACE
            ERROR_QUIET
        )
        
        if(HOMEBREW_QT5_VERSIONED_PREFIX AND EXISTS "${HOMEBREW_QT5_VERSIONED_PREFIX}")
            set(Qt5_DIR "${HOMEBREW_QT5_VERSIONED_PREFIX}/lib/cmake/Qt5")
            
            if(EXISTS "${Qt5_DIR}")
                find_package(Qt5 QUIET COMPONENTS Core Gui Widgets Test Concurrent OpenGL PATHS "${Qt5_DIR}" NO_DEFAULT_PATH)
                
                if(Qt5_FOUND)
                    set(QT5_FOUND TRUE PARENT_SCOPE)
                    set(QT5_DETECTION_METHOD "Homebrew (versioned)" PARENT_SCOPE)
                    set(QT5_INSTALL_PATH "${HOMEBREW_QT5_VERSIONED_PREFIX}" PARENT_SCOPE)
                    message(STATUS "Found Qt5 via Homebrew (versioned): ${Qt5_VERSION} at ${HOMEBREW_QT5_VERSIONED_PREFIX}")
                    return()
                endif()
            endif()
        endif()
    endif()
    
    # Method 2: Try Qt installer locations
    set(QT_INSTALLER_PATHS
        "~/Qt/5.15.2/clang_64"
        "~/Qt/5.15.1/clang_64"
        "~/Qt/5.15.0/clang_64"
        "~/Qt/5.14.2/clang_64"
        "~/Qt/5.14.1/clang_64"
        "~/Qt/5.14.0/clang_64"
        "~/Qt/5.13.2/clang_64"
        "/Applications/Qt/5.15.2/clang_64"
        "/Applications/Qt/5.15.1/clang_64"
        "/Applications/Qt/5.15.0/clang_64"
        "/Applications/Qt/5.14.2/clang_64"
        "/Applications/Qt/5.14.1/clang_64"
        "/Applications/Qt/5.14.0/clang_64"
        "/Applications/Qt/5.13.2/clang_64"
    )
    
    foreach(QT_PATH ${QT_INSTALLER_PATHS})
        if(EXISTS "${QT_PATH}/lib/cmake/Qt5")
            set(Qt5_DIR "${QT_PATH}/lib/cmake/Qt5")
            find_package(Qt5 QUIET COMPONENTS Core Gui Widgets Test Concurrent OpenGL PATHS "${Qt5_DIR}" NO_DEFAULT_PATH)
            
            if(Qt5_FOUND)
                set(QT5_FOUND TRUE PARENT_SCOPE)
                set(QT5_DETECTION_METHOD "Qt Installer" PARENT_SCOPE)
                set(QT5_INSTALL_PATH "${QT_PATH}" PARENT_SCOPE)
                message(STATUS "Found Qt5 via Qt installer: ${Qt5_VERSION} at ${QT_PATH}")
                return()
            endif()
        endif()
    endforeach()
    
    # Method 3: Try standard system paths
    set(QT5_SEARCH_PATHS
        "/usr/local/Qt5"
        "/usr/local"
        "/opt/local"
        "/usr"
    )
    
    foreach(SEARCH_PATH ${QT5_SEARCH_PATHS})
        if(EXISTS "${SEARCH_PATH}/lib/cmake/Qt5")
            find_package(Qt5 QUIET COMPONENTS Core Gui Widgets Test Concurrent OpenGL PATHS "${SEARCH_PATH}/lib/cmake/Qt5" NO_DEFAULT_PATH)
        endif()
        
        if(Qt5_FOUND)
            set(QT5_FOUND TRUE PARENT_SCOPE)
            set(QT5_DETECTION_METHOD "Standard Path" PARENT_SCOPE)
            set(QT5_INSTALL_PATH "${SEARCH_PATH}" PARENT_SCOPE)
            message(STATUS "Found Qt5 via standard path: ${Qt5_VERSION} at ${SEARCH_PATH}")
            return()
        endif()
    endforeach()
    
    # If we get here, Qt5 was not found
    message(WARNING "Qt5 not found via any detection method")
endfunction()

# Function to validate Qt5 installation
function(validate_qt5_installation)
    if(NOT Qt5_FOUND)
        return()
    endif()
    
    # Check for required Qt5 components
    set(REQUIRED_QT5_COMPONENTS Core Gui Widgets Test Concurrent OpenGL)
    set(MISSING_COMPONENTS "")
    
    foreach(COMPONENT ${REQUIRED_QT5_COMPONENTS})
        if(NOT TARGET Qt5::${COMPONENT})
            list(APPEND MISSING_COMPONENTS ${COMPONENT})
        endif()
    endforeach()
    
    if(MISSING_COMPONENTS)
        message(WARNING "Qt5 installation is missing required components: ${MISSING_COMPONENTS}")
        set(QT5_VALID FALSE PARENT_SCOPE)
    else()
        set(QT5_VALID TRUE PARENT_SCOPE)
        message(STATUS "Qt5 installation validated successfully")
    endif()
    
    # Check Qt5 version compatibility
    if(Qt5_VERSION VERSION_LESS "5.12.0")
        message(WARNING "Qt5 version ${Qt5_VERSION} is older than recommended minimum 5.12.0")
    endif()
endfunction()

# Function to generate dependency installation suggestions
function(generate_opencv_install_suggestions)
    if(OPENCV_FOUND)
        return()
    endif()
    
    message(STATUS "")
    message(STATUS "OpenCV not found. Installation suggestions:")
    message(STATUS "")
    
    if(MACOS_HOMEBREW_PREFIX)
        message(STATUS "Option 1 (Recommended): Install via Homebrew")
        message(STATUS "  brew install opencv")
        message(STATUS "")
    else()
        message(STATUS "Option 1: Install Homebrew first, then OpenCV")
        message(STATUS "  /bin/bash -c \"$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)\"")
        message(STATUS "  brew install opencv")
        message(STATUS "")
    endif()
    
    message(STATUS "Option 2: Download OpenCV.framework")
    message(STATUS "  Download from: https://opencv.org/releases/")
    message(STATUS "  Extract to: /Library/Frameworks/")
    message(STATUS "")
    
    message(STATUS "Option 3: Build from source")
    message(STATUS "  git clone https://github.com/opencv/opencv.git")
    message(STATUS "  cd opencv && mkdir build && cd build")
    message(STATUS "  cmake -DCMAKE_BUILD_TYPE=Release ..")
    message(STATUS "  make -j$(sysctl -n hw.ncpu)")
    message(STATUS "  sudo make install")
    message(STATUS "")
endfunction()

# Function to find Eigen3 on macOS
function(find_eigen3_macos)
    set(EIGEN3_FOUND FALSE PARENT_SCOPE)
    set(EIGEN3_DETECTION_METHOD "" PARENT_SCOPE)
    
    # Method 1: Try pkg-config first (most reliable for Homebrew installations)
    find_package(PkgConfig QUIET)
    if(PKG_CONFIG_FOUND)
        pkg_check_modules(EIGEN3_PC QUIET eigen3)
        if(EIGEN3_PC_FOUND)
            set(Eigen3_INCLUDE_DIRS ${EIGEN3_PC_INCLUDE_DIRS})
            set(Eigen3_VERSION ${EIGEN3_PC_VERSION})
            set(EIGEN3_FOUND TRUE PARENT_SCOPE)
            set(EIGEN3_DETECTION_METHOD "pkg-config" PARENT_SCOPE)
            set(EIGEN3_INSTALL_PATH "${EIGEN3_PC_PREFIX}" PARENT_SCOPE)
            set(Eigen3_INCLUDE_DIRS "${Eigen3_INCLUDE_DIRS}" PARENT_SCOPE)
            set(Eigen3_VERSION "${Eigen3_VERSION}" PARENT_SCOPE)
            message(STATUS "Found Eigen3 via pkg-config: ${Eigen3_VERSION} at ${EIGEN3_PC_PREFIX}")
            return()
        endif()
    endif()
    
    # Method 2: Try Homebrew Eigen3
    if(MACOS_HOMEBREW_PREFIX)
        execute_process(
            COMMAND brew --prefix eigen
            OUTPUT_VARIABLE HOMEBREW_EIGEN_PREFIX
            OUTPUT_STRIP_TRAILING_WHITESPACE
            ERROR_QUIET
        )
        
        if(HOMEBREW_EIGEN_PREFIX AND EXISTS "${HOMEBREW_EIGEN_PREFIX}")
            set(EIGEN3_INCLUDE_DIR "${HOMEBREW_EIGEN_PREFIX}/include/eigen3")
            
            if(EXISTS "${EIGEN3_INCLUDE_DIR}/Eigen/Core")
                set(Eigen3_INCLUDE_DIRS "${EIGEN3_INCLUDE_DIR}")
                
                # Try to determine version from Eigen headers
                if(EXISTS "${EIGEN3_INCLUDE_DIR}/Eigen/src/Core/util/Macros.h")
                    file(READ "${EIGEN3_INCLUDE_DIR}/Eigen/src/Core/util/Macros.h" EIGEN_MACROS_CONTENT)
                    string(REGEX MATCH "#define EIGEN_WORLD_VERSION ([0-9]+)" _ "${EIGEN_MACROS_CONTENT}")
                    set(EIGEN_WORLD_VERSION ${CMAKE_MATCH_1})
                    string(REGEX MATCH "#define EIGEN_MAJOR_VERSION ([0-9]+)" _ "${EIGEN_MACROS_CONTENT}")
                    set(EIGEN_MAJOR_VERSION ${CMAKE_MATCH_1})
                    string(REGEX MATCH "#define EIGEN_MINOR_VERSION ([0-9]+)" _ "${EIGEN_MACROS_CONTENT}")
                    set(EIGEN_MINOR_VERSION ${CMAKE_MATCH_1})
                    
                    if(EIGEN_WORLD_VERSION AND EIGEN_MAJOR_VERSION AND EIGEN_MINOR_VERSION)
                        set(Eigen3_VERSION "${EIGEN_WORLD_VERSION}.${EIGEN_MAJOR_VERSION}.${EIGEN_MINOR_VERSION}")
                    endif()
                endif()
                
                set(EIGEN3_FOUND TRUE PARENT_SCOPE)
                set(EIGEN3_DETECTION_METHOD "Homebrew" PARENT_SCOPE)
                set(EIGEN3_INSTALL_PATH "${HOMEBREW_EIGEN_PREFIX}" PARENT_SCOPE)
                set(Eigen3_INCLUDE_DIRS "${Eigen3_INCLUDE_DIRS}" PARENT_SCOPE)
                set(Eigen3_VERSION "${Eigen3_VERSION}" PARENT_SCOPE)
                message(STATUS "Found Eigen3 via Homebrew: ${Eigen3_VERSION} at ${HOMEBREW_EIGEN_PREFIX}")
                return()
            endif()
        endif()
    endif()
    
    # Method 3: Try CMake's built-in FindEigen3
    find_package(Eigen3 QUIET NO_MODULE)
    if(Eigen3_FOUND OR EIGEN3_FOUND)
        set(EIGEN3_FOUND TRUE PARENT_SCOPE)
        set(EIGEN3_DETECTION_METHOD "CMake FindEigen3" PARENT_SCOPE)
        set(EIGEN3_INSTALL_PATH "${EIGEN3_ROOT_DIR}" PARENT_SCOPE)
        message(STATUS "Found Eigen3 via CMake: ${Eigen3_VERSION}")
        return()
    endif()
    
    # Method 4: Try standard include paths
    set(EIGEN3_SEARCH_PATHS
        "/usr/local/include/eigen3"
        "/usr/include/eigen3"
        "/opt/local/include/eigen3"
        "/usr/local/include"
        "/usr/include"
        "/opt/local/include"
    )
    
    foreach(SEARCH_PATH ${EIGEN3_SEARCH_PATHS})
        if(EXISTS "${SEARCH_PATH}/Eigen/Core")
            set(Eigen3_INCLUDE_DIRS "${SEARCH_PATH}")
            set(EIGEN3_FOUND TRUE PARENT_SCOPE)
            set(EIGEN3_DETECTION_METHOD "Standard Path" PARENT_SCOPE)
            set(EIGEN3_INSTALL_PATH "${SEARCH_PATH}" PARENT_SCOPE)
            set(Eigen3_INCLUDE_DIRS "${Eigen3_INCLUDE_DIRS}" PARENT_SCOPE)
            message(STATUS "Found Eigen3 via standard path at ${SEARCH_PATH}")
            return()
        endif()
    endforeach()
    
    # If we get here, Eigen3 was not found
    message(WARNING "Eigen3 not found via any detection method")
endfunction()

# Function to validate Eigen3 installation
function(validate_eigen3_installation)
    if(NOT EIGEN3_FOUND)
        return()
    endif()
    
    # Debug output
    message(STATUS "DEBUG: Eigen3_INCLUDE_DIRS = ${Eigen3_INCLUDE_DIRS}")
    
    # Check if Eigen/Core header exists
    if(NOT EXISTS "${Eigen3_INCLUDE_DIRS}/Eigen/Core")
        message(WARNING "Eigen3 Core header not found at expected location: ${Eigen3_INCLUDE_DIRS}/Eigen/Core")
        set(EIGEN3_VALID FALSE PARENT_SCOPE)
        return()
    endif()
    
    # Check for essential Eigen modules
    set(REQUIRED_EIGEN_HEADERS "Eigen/Dense" "Eigen/Sparse" "Eigen/Geometry")
    set(MISSING_HEADERS "")
    
    foreach(HEADER ${REQUIRED_EIGEN_HEADERS})
        if(NOT EXISTS "${Eigen3_INCLUDE_DIRS}/${HEADER}")
            list(APPEND MISSING_HEADERS ${HEADER})
        endif()
    endforeach()
    
    if(MISSING_HEADERS)
        message(WARNING "Eigen3 installation is missing required headers: ${MISSING_HEADERS}")
        set(EIGEN3_VALID FALSE PARENT_SCOPE)
    else()
        set(EIGEN3_VALID TRUE PARENT_SCOPE)
        message(STATUS "Eigen3 installation validated successfully")
    endif()
    
    # Check Eigen3 version compatibility
    if(Eigen3_VERSION AND Eigen3_VERSION VERSION_LESS "3.3.0")
        message(WARNING "Eigen3 version ${Eigen3_VERSION} is older than recommended minimum 3.3.0")
    endif()
endfunction()

# Function to generate Qt5 installation suggestions
function(generate_qt5_install_suggestions)
    if(QT5_FOUND)
        return()
    endif()
    
    message(STATUS "")
    message(STATUS "Qt5 not found. Installation suggestions:")
    message(STATUS "")
    
    if(MACOS_HOMEBREW_PREFIX)
        message(STATUS "Option 1 (Recommended): Install via Homebrew")
        message(STATUS "  brew install qt@5")
        message(STATUS "")
    else()
        message(STATUS "Option 1: Install Homebrew first, then Qt5")
        message(STATUS "  /bin/bash -c \"$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)\"")
        message(STATUS "  brew install qt@5")
        message(STATUS "")
    endif()
    
    message(STATUS "Option 2: Download Qt5 from official installer")
    message(STATUS "  Download from: https://www.qt.io/download-qt-installer")
    message(STATUS "  Install to: ~/Qt/ or /Applications/Qt/")
    message(STATUS "")
    
    message(STATUS "Option 3: Build from source")
    message(STATUS "  git clone https://code.qt.io/qt/qt5.git")
    message(STATUS "  cd qt5 && git checkout 5.15")
    message(STATUS "  ./configure -opensource -confirm-license")
    message(STATUS "  make -j$(sysctl -n hw.ncpu)")
    message(STATUS "  sudo make install")
    message(STATUS "")
endfunction()

# Function to generate Eigen3 installation suggestions
function(generate_eigen3_install_suggestions)
    if(EIGEN3_FOUND)
        return()
    endif()
    
    message(STATUS "")
    message(STATUS "Eigen3 not found. Installation suggestions:")
    message(STATUS "")
    
    if(MACOS_HOMEBREW_PREFIX)
        message(STATUS "Option 1 (Recommended): Install via Homebrew")
        message(STATUS "  brew install eigen")
        message(STATUS "")
    else()
        message(STATUS "Option 1: Install Homebrew first, then Eigen3")
        message(STATUS "  /bin/bash -c \"$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)\"")
        message(STATUS "  brew install eigen")
        message(STATUS "")
    endif()
    
    message(STATUS "Option 2: Install via MacPorts")
    message(STATUS "  sudo port install eigen3")
    message(STATUS "")
    
    message(STATUS "Option 3: Download and install manually")
    message(STATUS "  Download from: https://eigen.tuxfamily.org/")
    message(STATUS "  Extract and copy headers to: /usr/local/include/eigen3/")
    message(STATUS "")
    
    message(STATUS "Option 4: Build from source")
    message(STATUS "  git clone https://gitlab.com/libeigen/eigen.git")
    message(STATUS "  cd eigen && mkdir build && cd build")
    message(STATUS "  cmake ..")
    message(STATUS "  sudo make install")
    message(STATUS "")
endfunction()

# Function to check dependency version compatibility
function(check_dependency_versions)
    set(VERSION_WARNINGS "")
    
    # Check OpenCV version
    if(OPENCV_FOUND AND OpenCV_VERSION)
        if(OpenCV_VERSION VERSION_LESS "4.0.0")
            list(APPEND VERSION_WARNINGS "OpenCV ${OpenCV_VERSION} is older than recommended minimum 4.0.0")
        elseif(OpenCV_VERSION VERSION_GREATER_EQUAL "5.0.0")
            list(APPEND VERSION_WARNINGS "OpenCV ${OpenCV_VERSION} is newer than tested versions - compatibility not guaranteed")
        endif()
    endif()
    
    # Check Qt5 version
    if(QT5_FOUND AND Qt5_VERSION)
        if(Qt5_VERSION VERSION_LESS "5.12.0")
            list(APPEND VERSION_WARNINGS "Qt5 ${Qt5_VERSION} is older than recommended minimum 5.12.0")
        elseif(Qt5_VERSION VERSION_GREATER_EQUAL "6.0.0")
            list(APPEND VERSION_WARNINGS "Qt version ${Qt5_VERSION} is Qt6 - Qt5 is required")
        endif()
    endif()
    
    # Check Eigen3 version
    if(EIGEN3_FOUND AND Eigen3_VERSION)
        if(Eigen3_VERSION VERSION_LESS "3.3.0")
            list(APPEND VERSION_WARNINGS "Eigen3 ${Eigen3_VERSION} is older than recommended minimum 3.3.0")
        endif()
    endif()
    
    # Report version warnings
    if(VERSION_WARNINGS)
        message(STATUS "")
        message(WARNING "Dependency version warnings:")
        foreach(WARNING ${VERSION_WARNINGS})
            message(WARNING "  ${WARNING}")
        endforeach()
        message(STATUS "")
    endif()
    
    set(DEPENDENCY_VERSION_WARNINGS "${VERSION_WARNINGS}" PARENT_SCOPE)
endfunction()

# Function to generate comprehensive dependency diagnostic report
function(generate_dependency_diagnostic)
    message(STATUS "")
    message(STATUS "=== macOS Dependency Diagnostic Report ===")
    message(STATUS "")
    
    # System information
    execute_process(COMMAND sw_vers -productVersion OUTPUT_VARIABLE MACOS_VERSION OUTPUT_STRIP_TRAILING_WHITESPACE ERROR_QUIET)
    execute_process(COMMAND uname -m OUTPUT_VARIABLE SYSTEM_ARCH OUTPUT_STRIP_TRAILING_WHITESPACE ERROR_QUIET)
    
    message(STATUS "System Information:")
    message(STATUS "  macOS Version: ${MACOS_VERSION}")
    message(STATUS "  Architecture: ${SYSTEM_ARCH}")
    message(STATUS "  CMake Version: ${CMAKE_VERSION}")
    message(STATUS "")
    
    # Homebrew status
    message(STATUS "Package Manager Status:")
    if(MACOS_HOMEBREW_PREFIX)
        message(STATUS "  Homebrew: Found at ${MACOS_HOMEBREW_PREFIX}")
        
        # Check Homebrew health
        execute_process(
            COMMAND brew doctor
            OUTPUT_VARIABLE BREW_DOCTOR_OUTPUT
            ERROR_VARIABLE BREW_DOCTOR_ERROR
            RESULT_VARIABLE BREW_DOCTOR_RESULT
            OUTPUT_STRIP_TRAILING_WHITESPACE
            ERROR_STRIP_TRAILING_WHITESPACE
        )
        
        if(BREW_DOCTOR_RESULT EQUAL 0)
            message(STATUS "  Homebrew Health: OK")
        else()
            message(STATUS "  Homebrew Health: Issues detected")
            message(STATUS "    Run 'brew doctor' for details")
        endif()
    else()
        message(STATUS "  Homebrew: Not found")
        
        # Check for MacPorts
        execute_process(COMMAND which port OUTPUT_VARIABLE MACPORTS_PATH OUTPUT_STRIP_TRAILING_WHITESPACE ERROR_QUIET)
        if(MACPORTS_PATH)
            message(STATUS "  MacPorts: Found at ${MACPORTS_PATH}")
        else()
            message(STATUS "  MacPorts: Not found")
        endif()
    endif()
    message(STATUS "")
    
    # Dependency status
    message(STATUS "Dependency Detection Results:")
    
    # OpenCV status
    if(OPENCV_FOUND)
        message(STATUS "  OpenCV: FOUND")
        message(STATUS "    Version: ${OpenCV_VERSION}")
        message(STATUS "    Method: ${OPENCV_DETECTION_METHOD}")
        message(STATUS "    Path: ${OPENCV_INSTALL_PATH}")
        if(OPENCV_VALID)
            message(STATUS "    Status: Valid")
        else()
            message(STATUS "    Status: Invalid - missing components")
        endif()
    else()
        message(STATUS "  OpenCV: NOT FOUND")
    endif()
    
    # Qt5 status
    if(QT5_FOUND)
        message(STATUS "  Qt5: FOUND")
        message(STATUS "    Version: ${Qt5_VERSION}")
        message(STATUS "    Method: ${QT5_DETECTION_METHOD}")
        message(STATUS "    Path: ${QT5_INSTALL_PATH}")
        if(QT5_VALID)
            message(STATUS "    Status: Valid")
        else()
            message(STATUS "    Status: Invalid - missing components")
        endif()
    else()
        message(STATUS "  Qt5: NOT FOUND")
    endif()
    
    # Eigen3 status
    if(EIGEN3_FOUND)
        message(STATUS "  Eigen3: FOUND")
        if(Eigen3_VERSION)
            message(STATUS "    Version: ${Eigen3_VERSION}")
        endif()
        message(STATUS "    Method: ${EIGEN3_DETECTION_METHOD}")
        message(STATUS "    Path: ${EIGEN3_INSTALL_PATH}")
        if(EIGEN3_VALID)
            message(STATUS "    Status: Valid")
        else()
            message(STATUS "    Status: Invalid - missing headers")
        endif()
    else()
        message(STATUS "  Eigen3: NOT FOUND")
    endif()
    
    message(STATUS "")
    
    # Version compatibility check
    check_dependency_versions()
    
    # Troubleshooting suggestions
    message(STATUS "Troubleshooting Tips:")
    message(STATUS "  1. Ensure Xcode Command Line Tools are installed:")
    message(STATUS "     xcode-select --install")
    message(STATUS "")
    message(STATUS "  2. Update Homebrew if using it:")
    message(STATUS "     brew update && brew upgrade")
    message(STATUS "")
    message(STATUS "  3. Clear CMake cache if changing dependencies:")
    message(STATUS "     rm -rf build/ && mkdir build")
    message(STATUS "")
    message(STATUS "  4. Set CMAKE_PREFIX_PATH for custom installations:")
    message(STATUS "     cmake -DCMAKE_PREFIX_PATH=/path/to/deps ..")
    message(STATUS "")
    message(STATUS "=== End Diagnostic Report ===")
    message(STATUS "")
endfunction()

# Function to generate installation script for all missing dependencies
function(generate_complete_install_script)
    set(MISSING_DEPS "")
    
    if(NOT OPENCV_FOUND)
        list(APPEND MISSING_DEPS "opencv")
    endif()
    
    if(NOT QT5_FOUND)
        list(APPEND MISSING_DEPS "qt@5")
    endif()
    
    if(NOT EIGEN3_FOUND)
        list(APPEND MISSING_DEPS "eigen")
    endif()
    
    if(MISSING_DEPS)
        message(STATUS "")
        message(STATUS "=== Quick Installation Script ===")
        message(STATUS "")
        
        if(NOT MACOS_HOMEBREW_PREFIX)
            message(STATUS "# Install Homebrew first")
            message(STATUS "/bin/bash -c \"$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)\"")
            message(STATUS "")
        endif()
        
        message(STATUS "# Install missing dependencies")
        string(REPLACE ";" " " DEPS_STRING "${MISSING_DEPS}")
        message(STATUS "brew install ${DEPS_STRING}")
        message(STATUS "")
        
        message(STATUS "# Verify installations")
        foreach(DEP ${MISSING_DEPS})
            message(STATUS "brew list ${DEP}")
        endforeach()
        message(STATUS "")
        
        message(STATUS "=== End Installation Script ===")
        message(STATUS "")
    endif()
endfunction()