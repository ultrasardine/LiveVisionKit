# Changelog

All notable changes to OpenVisionKit will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- **Architecture documentation** - Comprehensive architectural overview with Mermaid diagrams showing data flow and component relationships

### Improved
- **Architecture diagram structure** - Enhanced Mermaid diagram with improved visual hierarchy, clearer component groupings, and better data flow representation
- **Architecture diagram readability** - Simplified node labels with multi-line descriptions for better visual clarity and reduced complexity
- **Component organization** - Restructured architecture diagram to show distinct processing layers (Input, Enhancement, Geometric, Computer Vision, GPU Acceleration, Application Interface, Configuration, Data Storage, Utility, Output)
- **Data flow visualization** - Added clear distinction between main data flow (solid lines) and supporting connections (dotted lines) for better understanding of system architecture
- **macOS build support** - ✅ Complete implementation with automatic dependency detection and configuration
- **macOS OBS plugin integration** - ✅ Native bundle structure (.dylib) and compatibility layer with version detection
- **macOS video editor support** - ✅ AVFoundation framework integration for native codec support and hardware acceleration
- **Universal binary support** - ✅ Intel (x86_64) and Apple Silicon (ARM64) architectures with automatic configuration
- **Homebrew integration** - ✅ Automatic dependency detection, installation, and path discovery via setup script
- **macOS frameworks integration** - ✅ CoreFoundation, CoreVideo, Accelerate, OpenCL, Metal Performance Shaders support
- **Security and compliance** - ✅ Code signing preparation, hardened runtime compatibility, privacy permission handling
- **Distribution packaging** - ✅ DMG, PKG, and ZIP package creation with automated bundle structure
- **Testing framework** - ✅ Comprehensive unit testing with macOS-specific validation and memory leak prevention
- **Global development practices** - Standardized Python package management (uv) and terminal output management guidelines
- Comprehensive open source project compliance
- GitHub issue and PR templates
- Security policy and vulnerability reporting process
- Code of conduct for community guidelines
- Contributing guidelines with development standards
- Industry standards compliance documentation

### Changed
- Enhanced development safety guidelines with macOS-specific requirements
- Improved documentation structure with macOS build instructions
- Updated steering documents with workflow requirements
- **BREAKING**: Project renamed from LiveVisionKit to OpenVisionKit
- **Build system**: Automatic macOS detection and configuration
- **OBS plugin**: macOS-specific installation paths and bundle structure
- **Video processing**: Platform-specific optimizations for macOS hardware acceleration

### Security
- Added security policy and vulnerability disclosure process
- Enhanced build system security features
- Improved input validation requirements

## Project Status

**Note**: OpenVisionKit is a community-driven fork that evolved from the original LiveVisionKit project (which is on indefinite pause by Crowsinc). This community fork under `ultrasardine` continues development with focus on:

- ✅ **macOS platform support** - **COMPLETED**: Full implementation with universal binary support, automated build system, OBS plugin integration, and distribution packaging
- 🔄 **Community-driven improvements** - Ongoing enhancements and feature additions
- 🔒 **Security and stability enhancements** - Continuous security improvements
- 📋 **Open source best practices compliance** - Industry standards adherence

### macOS Implementation Status: COMPLETED ✅

All core macOS build support features have been successfully implemented and tested:
- Build system with automatic dependency detection
- OBS Studio plugin with native macOS bundle structure
- Video editor with AVFoundation framework integration
- Universal binary support (Intel + Apple Silicon)
- Security compliance and code signing preparation
- Automated setup and build scripts
- Distribution packaging (DMG, PKG, ZIP)

## Previous Releases

For information about previous releases from the original repository, please refer to:
- [Original Release History](https://github.com/Crowsinc/LiveVisionKit/releases)
- [Original Project Wiki](https://github.com/Crowsinc/LiveVisionKit/wiki)

---

## Release Types

### Major Releases (X.0.0)
- Breaking API changes
- Major new features
- Platform support additions
- Significant architecture changes

### Minor Releases (X.Y.0)
- New features and enhancements
- Performance improvements
- New filters or capabilities
- Non-breaking API additions

### Patch Releases (X.Y.Z)
- Bug fixes
- Security patches
- Documentation updates
- Build system improvements

---

## Contributing to Changelog

When contributing changes, please:

1. **Add entries** to the `[Unreleased]` section
2. **Use appropriate categories**: Added, Changed, Deprecated, Removed, Fixed, Security
3. **Follow the format**: Brief description with issue/PR references
4. **Include breaking changes** in the Changed section with clear migration notes
5. **Reference issues/PRs** using `(#123)` format

### Example Entry Format

```markdown
### Added
- New video stabilization algorithm with improved performance (#123)
- macOS support for OBS Studio plugin (#456)

### Changed
- **BREAKING**: Updated VideoFilter API to support async processing (#789)
- Improved memory usage in filter chains by 15% (#101)

### Fixed
- Fixed memory leak in OpenCV integration (#234)
- Resolved thread safety issue in composite filters (#567)

### Security
- Fixed buffer overflow vulnerability in video decoder (#890)
```

---

**Note**: This changelog follows the community fork development. For historical changes from the original project, please refer to the original repository's release notes.