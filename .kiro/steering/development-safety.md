---
inclusion: always
---

# OpenVisionKit Development Safety Guidelines

## Project Overview

OpenVisionKit (OVK) is a community-driven, open source real-time video processing library that evolved from the original LiveVisionKit project. It provides professional-grade video filters for livestreaming and recorded video processing.

### Key Characteristics
- **Language**: C++20 with OpenCV, Eigen3, and Qt5 dependencies
- **License**: GPL v3 (copyleft - requires derivative works to be open source)
- **Platforms**: Windows, Linux, and macOS (in active development)
- **Architecture**: Modular filter-based system with OBS Studio plugin integration
- **Core Features**: Video stabilization, adaptive de-blocking, lens correction, image enhancement, batch processing
- **Community Status**: Volunteer-driven development with no commercial backing

## Critical Safety Requirements

### 1. Memory Safety & Resource Management

**MANDATORY PRACTICES:**
- Always use RAII patterns for resource management
- Prefer smart pointers (`std::unique_ptr`, `std::shared_ptr`) over raw pointers
- Use OpenCV's `cv::UMat` for GPU-accelerated operations when possible
- Implement proper exception safety (basic/strong guarantee)
- Never ignore return values from OpenCV functions

**FORBIDDEN PATTERNS:**
```cpp
// BAD: Raw pointer without RAII
cv::Mat* frame = new cv::Mat();
// ... code that might throw
delete frame; // May never execute

// BAD: Ignoring OpenCV errors
cv::VideoCapture cap(0);
cap >> frame; // No error checking

// GOOD: RAII with smart pointers
auto frame = std::make_unique<cv::UMat>();

// GOOD: Error checking
cv::VideoCapture cap(0);
if (!cap.isOpened()) {
    throw std::runtime_error("Cannot open camera");
}
```

### 2. Thread Safety & Concurrency

**REQUIREMENTS:**
- All filter operations must be thread-safe or clearly documented as single-threaded
- Use `std::mutex`, `std::shared_mutex`, or lock-free data structures appropriately
- OpenCV operations are generally NOT thread-safe on the same object
- GPU operations (OpenCL) require careful context management

**IMPLEMENTATION PATTERN:**
```cpp
class ThreadSafeFilter {
private:
    mutable std::shared_mutex m_mutex;
    // ... member variables
    
public:
    void apply(const VideoFrame& input, VideoFrame& output) {
        std::shared_lock lock(m_mutex); // Read operations
        // ... filter logic
    }
    
    void configure(const Settings& settings) {
        std::unique_lock lock(m_mutex); // Write operations
        // ... configuration logic
    }
};
```

### 3. Input Validation & Assertions

**MANDATORY CHECKS:**
- Always validate input frame dimensions, format, and data integrity
- Use OVK assertion macros for precondition checking
- Validate configuration parameters within acceptable ranges
- Check for null/empty inputs before processing

**ASSERTION USAGE:**
```cpp
void processFrame(const VideoFrame& input, VideoFrame& output) {
    OVK_ASSERT(!input.empty());
    OVK_ASSERT(input.has_known_format());
    OVK_ASSERT_RANGE(input.width, 1, 8192);
    OVK_ASSERT_RANGE(input.height, 1, 8192);
    
    // ... processing logic
}
```

### 4. Performance & Real-time Constraints

**CRITICAL REQUIREMENTS:**
- All filters must process frames within real-time constraints (typically <33ms for 30fps)
- Use profiling (`VideoFilter::timings()`) to monitor performance
- Prefer GPU-accelerated operations (`cv::UMat`) for computationally intensive tasks
- Implement frame dropping/skipping mechanisms for overload scenarios

**PERFORMANCE MONITORING:**
```cpp
void apply(VideoFrame&& input, VideoFrame& output, const bool profile = true) {
    if (profile) {
        // Automatic timing measurement built into VideoFilter base class
    }
    // ... filter implementation
}
```

### 5. Error Handling & Recovery

**ERROR HANDLING STRATEGY:**
- Use exceptions for unrecoverable errors (invalid input, system failures)
- Return error codes or optional values for recoverable failures
- Implement graceful degradation when possible
- Log errors appropriately using OVK logging system

**IMPLEMENTATION PATTERN:**
```cpp
class RobustFilter : public VideoFilter {
protected:
    void filter(VideoFrame&& input, VideoFrame& output) override {
        try {
            // Primary processing path
            processFrame(std::move(input), output);
        } catch (const cv::Exception& e) {
            // OpenCV-specific error handling
            OVK_LOG_ERROR("OpenCV error: " << e.what());
            // Fallback: pass through input unchanged
            input.copyTo(output);
        } catch (const std::exception& e) {
            // General error handling
            OVK_LOG_ERROR("Filter error: " << e.what());
            throw; // Re-throw if cannot recover
        }
    }
};
```

## Build System Safety

### 1. Dependency Management

**REQUIREMENTS:**
- Pin specific versions of all dependencies (OpenCV 4.8.0, Eigen 3.4, etc.)
- Verify dependency integrity before building
- Use static linking where possible to avoid runtime dependency issues
- Document all system requirements clearly

### 2. Compilation Safety

**MANDATORY FLAGS:**
```cmake
# Enable all warnings and treat them as errors
set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -Wall -Wextra -Werror")

# Enable address sanitizer in debug builds
if(CMAKE_BUILD_TYPE STREQUAL "Debug")
    set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -fsanitize=address -fno-omit-frame-pointer")
endif()

# Enable optimization and security features in release
if(CMAKE_BUILD_TYPE STREQUAL "Release")
    set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -O3 -DNDEBUG -fstack-protector-strong")
endif()
```

### 3. Platform-Specific Considerations

**WINDOWS:**
- Use MSVC runtime library consistently (`MultiThreaded$<$<CONFIG:Debug>:Debug>`)
- Handle path separators correctly
- Be aware of DLL loading security implications

**LINUX:**
- Ensure proper library linking order
- Handle Qt5 dependencies correctly
- Use appropriate compiler flags for target architecture

**MACOS:**
- Use appropriate deployment target (macOS 10.15+)
- Handle universal binary builds (x86_64 + arm64)
- Use system frameworks (CoreFoundation, CoreVideo, Accelerate)
- Follow Apple security guidelines (code signing, hardened runtime)

## Security Considerations

### 1. Input Sanitization

**REQUIREMENTS:**
- Validate all external inputs (video files, network streams, configuration files)
- Implement bounds checking for all array/buffer operations
- Sanitize file paths to prevent directory traversal attacks
- Validate image dimensions to prevent integer overflow

### 2. Memory Protection

**IMPLEMENTATION:**
- Use stack canaries and ASLR in release builds
- Avoid buffer overflows through proper bounds checking
- Clear sensitive data from memory when no longer needed
- Use secure memory allocation for cryptographic operations (if any)

### 3. Third-party Integration Safety

**OBS STUDIO PLUGIN:**
- Follow OBS plugin security guidelines
- Validate all data received from OBS
- Handle plugin lifecycle events properly
- Implement proper cleanup on plugin unload

## Testing & Quality Assurance

### 1. Mandatory Testing

**REQUIREMENTS:**
- Unit tests for all core algorithms
- Integration tests for filter chains
- Performance regression tests
- Memory leak detection (Valgrind/AddressSanitizer)
- Thread safety testing under load

### 2. Code Review Process

**MANDATORY REVIEWS:**
- All changes to core filter algorithms
- Performance-critical code paths
- Memory management code
- Thread synchronization code
- Public API changes

### 3. Continuous Integration

**CI PIPELINE MUST INCLUDE:**
- Compilation on all supported platforms
- Static analysis (cppcheck, clang-static-analyzer)
- Dynamic analysis (AddressSanitizer, ThreadSanitizer)
- Performance benchmarking
- License compliance checking

## Documentation Requirements

### 1. Code Documentation

**MANDATORY:**
- Doxygen comments for all public APIs
- Performance characteristics documentation
- Thread safety guarantees
- Memory ownership semantics
- Exception safety guarantees

### 2. Architecture Documentation

**REQUIRED DOCUMENTS:**
- Filter pipeline architecture
- Memory management strategy
- Threading model
- Performance optimization guidelines
- Security threat model

## Deployment Safety

### 1. Release Process

**MANDATORY STEPS:**
- Security audit of all changes
- Performance regression testing
- Compatibility testing with target OBS versions
- License compliance verification
- Digital signature of release binaries

### 2. Version Management

**REQUIREMENTS:**
- Semantic versioning (MAJOR.MINOR.PATCH)
- Clear changelog with security implications
- Deprecation notices for API changes
- Migration guides for breaking changes

## Emergency Procedures

### 1. Security Incident Response

**IMMEDIATE ACTIONS:**
- Disable affected functionality if possible
- Document the incident thoroughly
- Notify users through appropriate channels
- Prepare security patches with priority

### 2. Critical Bug Response

**ESCALATION PROCESS:**
- Assess impact on real-time performance
- Determine if workaround is possible
- Prioritize fix based on severity
- Test fix thoroughly before release

## Compliance & Legal

### 1. GPL v3 Compliance

**REQUIREMENTS:**
- All derivative works must be GPL v3 compatible
- Provide source code for all distributed binaries
- Include proper copyright notices
- Document all third-party licenses

### 2. Patent Considerations

**AWARENESS:**
- Video processing algorithms may be patent-encumbered
- Research patent landscape before implementing new algorithms
- Document patent research and decisions
- Consider alternative implementations if patent issues arise

## Development Workflow

### 1. GitHub Integration

**MANDATORY PRACTICES:**
- Always use GitHub CLI (`gh`) for issue and repository interactions
- MCP GitHub tools may have permission limitations - use `gh` as primary method
- Update issue tracking after significant code changes or milestones
- Document progress and decisions in GitHub issues for transparency

**PREFERRED COMMANDS:**
```bash
# Issue management
gh issue create --title "Title" --body "Description"
gh issue comment <issue-number> --body "Update message"
gh issue close <issue-number>

# Repository operations
gh repo fork <owner/repo>
gh repo view --json <fields>
gh pr create --title "Title" --body "Description"
```

### 2. Documentation Updates

**MANDATORY REQUIREMENTS:**
- Update relevant documentation after ANY code change
- Maintain consistency between code, comments, and external documentation
- Update README files when adding new features or changing build processes
- Keep API documentation synchronized with code changes
- Update build instructions when modifying CMake configuration

**DOCUMENTATION HIERARCHY:**
1. **Inline Code Comments**: Document complex algorithms and safety-critical sections
2. **Header Documentation**: Doxygen comments for all public APIs
3. **README Updates**: Build instructions, feature descriptions, platform support
4. **Architecture Documentation**: High-level design changes and system interactions
5. **Issue Tracking**: Progress updates and decision rationale

### 3. Industry Standards Compliance

**MANDATORY ADHERENCE:**
- Follow all applicable industry standards and best practices for implemented technologies
- Comply with technology-specific guidelines when making code changes
- Research and apply current standards before implementing new features
- Document deviations from standards with clear justification

**TECHNOLOGY-SPECIFIC STANDARDS:**

**C++20 Standards:**
- Follow ISO C++20 standard and Core Guidelines (https://isocpp.github.io/CppCoreGuidelines/)
- Use modern C++ idioms and avoid deprecated features
- Apply RAII, move semantics, and smart pointers consistently
- Follow naming conventions: PascalCase for classes, camelCase for functions/variables

**CMake Best Practices:**
- Follow CMake 3.16+ modern practices and target-based approach
- Use `target_link_libraries()`, `target_include_directories()`, `target_compile_features()`
- Avoid global commands like `include_directories()` and `link_directories()`
- Implement proper dependency management with `find_package()` and `FetchContent`

**OpenCV Integration:**
- Follow OpenCV 4.x API guidelines and best practices
- Use `cv::UMat` for GPU acceleration when available
- Implement proper error checking for all OpenCV operations
- Follow OpenCV memory management patterns and avoid memory leaks

**Qt5 Framework:**
- Follow Qt5 coding conventions and signal/slot patterns
- Use Qt5's memory management (parent-child relationships)
- Implement proper event handling and thread safety with Qt
- Follow Qt5 naming conventions and MOC requirements

**OBS Studio Plugin Development:**
- Adhere to OBS Studio plugin API guidelines and lifecycle management
- Follow OBS plugin security and stability requirements
- Implement proper resource cleanup and error handling
- Use OBS-provided logging and configuration systems

**macOS Development (when applicable):**
- Follow Apple's macOS development guidelines and Human Interface Guidelines
- Comply with App Store guidelines if distribution is planned
- Use Apple's recommended frameworks (AVFoundation, Core Video, Metal)
- Implement proper code signing and notarization preparation
- Follow macOS security best practices (hardened runtime, SIP compatibility)

**Git and Version Control:**
- Follow conventional commit message format
- Use semantic versioning for releases
- Maintain clean commit history with meaningful messages
- Follow GitFlow or GitHub Flow branching strategies

**Security Standards:**
- Apply OWASP guidelines for secure coding practices
- Follow platform-specific security recommendations
- Implement input validation and sanitization consistently
- Use secure coding practices for memory management and data handling

---

**REMEMBER: This project handles real-time video processing where performance, stability, and safety are paramount. When in doubt, prioritize safety over performance, and always test thoroughly under realistic conditions.**