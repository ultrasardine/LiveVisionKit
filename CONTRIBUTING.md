# Contributing to OpenVisionKit

Thank you for your interest in contributing to OpenVisionKit! This document provides guidelines and information for contributors.

## 🚨 Project Status

**OpenVisionKit** is a community-driven fork that evolved from the original LiveVisionKit project (which is on indefinite pause). This project operates entirely through volunteer contributions under the GPL v3 license.

## 📋 Table of Contents

- [Code of Conduct](#code-of-conduct)
- [Getting Started](#getting-started)
- [Development Setup](#development-setup)
- [Contributing Guidelines](#contributing-guidelines)
- [Pull Request Process](#pull-request-process)
- [Issue Reporting](#issue-reporting)
- [Development Standards](#development-standards)
- [License](#license)

## Code of Conduct

This project adheres to a [Code of Conduct](CODE_OF_CONDUCT.md). By participating, you are expected to uphold this code.

## Getting Started

### Prerequisites

- **Operating System**: Windows 10+, Linux (Ubuntu 18.04+), or macOS 10.15+ (with our macOS support)
- **Compiler**: C++20 compatible compiler (GCC 10+, Clang 12+, MSVC 2019+)
- **CMake**: Version 3.16 or higher
- **Dependencies**: OpenCV 4.8.0+, Eigen3 3.4+, Qt5 5.15+

### Quick Start

1. **Fork the repository** on GitHub
2. **Clone your fork** locally:
   ```bash
   git clone https://github.com/YOUR_USERNAME/OpenVisionKit.git
   cd OpenVisionKit
   ```
3. **Set up the development environment**:
   ```bash
   # Linux/macOS
   ./Scripts/setup_deb.sh  # or setup_macos.sh for macOS
   
   # Windows
   .\Scripts\setup_w64.ps1
   ```
4. **Build the project**:
   ```bash
   mkdir build && cd build
   cmake ..
   make -j$(nproc)  # or cmake --build . on Windows
   ```

## Development Setup

### Environment Configuration

1. **Install dependencies** using the provided setup scripts
2. **Configure your IDE** with the project's coding standards
3. **Set up pre-commit hooks** (recommended):
   ```bash
   # Install pre-commit (use uv for Python package management)
   uv pip install pre-commit
   pre-commit install
   ```

### Build Configurations

- **Debug**: Full debugging symbols, AddressSanitizer enabled
- **Release**: Optimized build with security features
- **RelWithDebInfo**: Optimized with debug symbols for profiling

## Contributing Guidelines

### Types of Contributions

We welcome various types of contributions:

- 🐛 **Bug fixes**
- ✨ **New features** (especially platform support improvements)
- 📚 **Documentation improvements**
- 🧪 **Test coverage enhancements**
- 🔧 **Build system improvements**
- 🌐 **Translations** (via [Crowdin](https://crowdin.com/project/openvisionkit))

### Before You Start

1. **Check existing issues** to avoid duplicate work
2. **Review the architecture** in [Architecture Documentation](openvisionkit_architecture.md) to understand system design
3. **Create an issue** for significant changes to discuss the approach
4. **Follow the development safety guidelines** in `.kiro/steering/development-safety.md`
5. **Ensure your changes align** with the project's real-time performance requirements

### Development Standards

#### Code Quality Requirements

- **Architecture Compliance**: Follow the modular filter-based design described in [Architecture Documentation](openvisionkit_architecture.md)
- **Memory Safety**: Use RAII patterns, smart pointers, and proper exception handling
- **Thread Safety**: All filter operations must be thread-safe or clearly documented
- **Performance**: Maintain real-time constraints (<33ms per frame for 30fps)
- **Input Validation**: Always validate inputs and handle edge cases
- **Error Handling**: Implement graceful degradation and proper error recovery

#### Development Workflow Standards

- **Python Package Management**: Always use `uv` instead of `pip` for Python dependencies
- **Terminal Output Management**: Use temporary files for long content (commits, issue comments) instead of direct terminal output
- **Documentation Synchronization**: Update all relevant documentation when making code changes

#### Code Style

- **C++20 Standards**: Follow ISO C++20 and Core Guidelines
- **Naming Conventions**: PascalCase for classes, camelCase for functions/variables
- **Documentation**: Doxygen comments for all public APIs
- **Testing**: Unit tests for all new functionality

#### Platform Compliance

- **Windows**: MSVC compatibility, proper DLL handling
- **Linux**: GCC/Clang compatibility, proper library linking
- **macOS**: Apple framework integration, security compliance

## Pull Request Process

### Before Submitting

1. **Ensure all tests pass**:
   ```bash
   cd build
   ctest --output-on-failure
   ```
2. **Run static analysis**:
   ```bash
   # Install tools if needed (use uv for Python tools)
   sudo apt-get install cppcheck clang-tidy
   uv pip install --system codespell  # For spell checking
   
   # Run analysis
   cppcheck --enable=all --std=c++20 OpenVisionKit/
   clang-tidy OpenVisionKit/**/*.cpp
   ```
3. **Check memory leaks** (Debug builds have AddressSanitizer enabled)
4. **Update documentation** for any API changes
5. **Add tests** for new functionality

### Pull Request Template

When creating a pull request, please:

1. **Use the provided PR template**
2. **Reference related issues** using `Fixes #123` or `Closes #123`
3. **Provide clear description** of changes and rationale
4. **Include testing information** and performance impact
5. **Update CHANGELOG.md** if applicable

### Review Process

1. **Automated checks** must pass (CI/CD pipeline)
2. **Code review** by maintainers or experienced contributors
3. **Testing** on multiple platforms if applicable
4. **Performance validation** for filter-related changes
5. **Documentation review** for user-facing changes

## Issue Reporting

### Bug Reports

Use the [Issue Report template](.github/ISSUE_TEMPLATE/issue-report.md) and include:

- **System specifications** (OS, GPU, CPU, versions)
- **OBS Studio log** (if applicable)
- **Clear reproduction steps**
- **Expected vs actual behavior**
- **Supporting evidence** (videos, screenshots)

### Feature Requests

Use the [Feature Request template](.github/ISSUE_TEMPLATE/feature-request.md) and include:

- **Clear feature description**
- **Use cases and rationale**
- **Examples or research references**
- **Implementation considerations**

### Security Issues

For security vulnerabilities, please see our [Security Policy](SECURITY.md).

## Development Standards

### Mandatory Requirements

- **GPL v3 Compliance**: All contributions must be compatible with GPL v3
- **Safety First**: Follow all safety guidelines in the steering document
- **Real-time Performance**: Maintain <33ms processing time per frame
- **Cross-platform Compatibility**: Test on supported platforms
- **Documentation**: Update docs for any user-facing changes

### Testing Requirements

- **Unit Tests**: Required for all new algorithms and core functionality
- **Integration Tests**: Required for filter chains and plugin interactions
- **Performance Tests**: Required for performance-critical changes
- **Memory Leak Tests**: Use AddressSanitizer in debug builds
- **Thread Safety Tests**: Required for concurrent operations

### Continuous Integration

Our CI pipeline includes:

- **Multi-platform builds** (Windows, Linux, macOS)
- **Static analysis** (cppcheck, clang-static-analyzer)
- **Dynamic analysis** (AddressSanitizer, ThreadSanitizer)
- **Performance benchmarking**
- **License compliance checking**

## Getting Help

- **GitHub Issues**: Use GitHub issues for bug reports and feature requests
- **GitHub Discussions**: Use GitHub Discussions for general questions and community support
- **Wiki**: Check the [project wiki](https://github.com/ultrasardine/OpenVisionKit/wiki) for documentation

## Recognition

Contributors are recognized in:

- **CHANGELOG.md** for significant contributions
- **README.md** contributors section
- **Git commit history** preserves all contribution records

## License

By contributing to OpenVisionKit, you agree that your contributions will be licensed under the [GPL v3 License](LICENSE).

---

**Thank you for contributing to OpenVisionKit!** 🎉

Your contributions help make real-time video processing accessible to creators worldwide.