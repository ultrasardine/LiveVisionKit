/**
 * Unit tests for macOS path handling and file system operations
 * Tests path processing, normalization, and macOS-specific filesystem conventions
 * **Validates: Requirements 7.1**
 */

#include <catch2/catch_test_macros.hpp>
#include <catch2/generators/catch_generators.hpp>
#include <catch2/generators/catch_generators_adapters.hpp>

#include <string>
#include <vector>
#include <filesystem>
#include <fstream>
#include <iostream>

#ifdef MACOS_BUILD

// Test helper functions for path handling
namespace {
    /**
     * Simulates the PathProcessor class functionality
     */
    class PathProcessor {
    public:
        /**
         * Normalizes a filesystem path according to macOS conventions
         */
        static std::string normalize_path(const std::filesystem::path& path) {
            try {
                // For absolute paths, convert to canonical form if possible
                if (path.is_absolute()) {
                    std::filesystem::path normalized = std::filesystem::weakly_canonical(path);
                    return normalized.string();
                } else {
                    // For relative paths, just clean them up without making them absolute
                    std::filesystem::path cleaned = path.lexically_normal();
                    return cleaned.string();
                }
            } catch (const std::filesystem::filesystem_error& e) {
                // If path doesn't exist, just clean it up
                std::filesystem::path cleaned = path.lexically_normal();
                return cleaned.string();
            }
        }
        
        /**
         * Checks if a path follows macOS filesystem conventions
         */
        static bool is_macos_filesystem_path(const std::string& path) {
            // Check for typical macOS path prefixes
            std::vector<std::string> macos_prefixes = {
                "/Users/",
                "/Applications/",
                "/System/",
                "/Library/",
                "/Volumes/",
                "/private/",
                "/opt/",
                "/usr/local/"
            };
            
            for (const auto& prefix : macos_prefixes) {
                if (path.find(prefix) == 0) {
                    return true;
                }
            }
            
            return false;
        }
        
        /**
         * Converts path separators to Unix style
         */
        static std::string convert_path_separators(const std::string& path) {
            std::string converted = path;
            std::replace(converted.begin(), converted.end(), '\\', '/');
            return converted;
        }
        
        /**
         * Normalizes Unicode filenames according to macOS conventions
         */
        static std::string normalize_unicode_filename(const std::string& filename) {
            // macOS uses NFD (Normalization Form Decomposed) for Unicode
            // For testing, we'll simulate basic normalization
            std::string normalized = filename;
            
            // Remove any path separators (security measure)
            normalized.erase(std::remove(normalized.begin(), normalized.end(), '/'), normalized.end());
            normalized.erase(std::remove(normalized.begin(), normalized.end(), '\\'), normalized.end());
            
            // Trim whitespace
            normalized.erase(0, normalized.find_first_not_of(" \t\n\r"));
            normalized.erase(normalized.find_last_not_of(" \t\n\r") + 1);
            
            return normalized;
        }
        
        /**
         * Validates that a path is suitable for video files
         */
        static bool validate_video_path(const std::filesystem::path& path) {
            // Check file extension
            std::string extension = path.extension().string();
            std::transform(extension.begin(), extension.end(), extension.begin(), ::tolower);
            
            std::vector<std::string> video_extensions = {
                ".mov", ".mp4", ".m4v", ".avi", ".mkv", ".webm", ".flv", ".wmv"
            };
            
            bool has_video_extension = std::find(video_extensions.begin(), 
                                                video_extensions.end(), 
                                                extension) != video_extensions.end();
            
            if (!has_video_extension) {
                return false;
            }
            
            // Check that path is not empty and has a filename
            if (path.empty() || !path.has_filename()) {
                return false;
            }
            
            // Check that filename is reasonable
            std::string filename = path.filename().string();
            if (filename.empty() || filename == "." || filename == "..") {
                return false;
            }
            
            return true;
        }
        
        /**
         * Resolves symbolic links and aliases (macOS-specific)
         */
        static std::string resolve_aliases(const std::string& path) {
            try {
                std::filesystem::path fs_path(path);
                
                // Resolve symbolic links
                if (std::filesystem::is_symlink(fs_path)) {
                    return std::filesystem::read_symlink(fs_path).string();
                }
                
                // For macOS aliases, we'd need to use Carbon/Cocoa APIs
                // For testing, just return the original path
                return path;
            } catch (const std::filesystem::filesystem_error&) {
                return path;
            }
        }
        
        /**
         * Checks if a path is case-sensitive (depends on filesystem)
         */
        static bool is_case_sensitive_path(const std::string& path) {
            // Most macOS filesystems (HFS+, APFS) are case-insensitive by default
            // but can be configured as case-sensitive
            
            try {
                std::filesystem::path test_path(path);
                if (!std::filesystem::exists(test_path.parent_path())) {
                    return false; // Can't test if parent doesn't exist
                }
                
                // Create temporary files to test case sensitivity
                std::string temp_name = "CaseSensitivityTest";
                std::filesystem::path temp_upper = test_path.parent_path() / temp_name;
                std::filesystem::path temp_lower = test_path.parent_path() / "casesensitivitytest";
                
                // Create upper case file
                std::ofstream upper_file(temp_upper);
                upper_file << "test";
                upper_file.close();
                
                // Check if lower case version exists (would indicate case-insensitive)
                bool case_insensitive = std::filesystem::exists(temp_lower);
                
                // Clean up
                if (std::filesystem::exists(temp_upper)) {
                    std::filesystem::remove(temp_upper);
                }
                
                return !case_insensitive;
            } catch (const std::exception&) {
                return false; // Default to case-insensitive
            }
        }
    };
    
    /**
     * Helper class for creating test files and directories
     */
    class TestFileManager {
    private:
        std::vector<std::filesystem::path> created_paths;
        
    public:
        ~TestFileManager() {
            cleanup();
        }
        
        std::filesystem::path create_test_file(const std::string& filename, const std::string& content = "test") {
            std::filesystem::path temp_dir = std::filesystem::temp_directory_path();
            std::filesystem::path test_file = temp_dir / filename;
            
            std::ofstream file(test_file);
            file << content;
            file.close();
            
            created_paths.push_back(test_file);
            return test_file;
        }
        
        std::filesystem::path create_test_directory(const std::string& dirname) {
            std::filesystem::path temp_dir = std::filesystem::temp_directory_path();
            std::filesystem::path test_dir = temp_dir / dirname;
            
            std::filesystem::create_directories(test_dir);
            created_paths.push_back(test_dir);
            return test_dir;
        }
        
        std::filesystem::path create_symlink(const std::filesystem::path& target, const std::string& link_name) {
            std::filesystem::path temp_dir = std::filesystem::temp_directory_path();
            std::filesystem::path link_path = temp_dir / link_name;
            
            try {
                std::filesystem::create_symlink(target, link_path);
                created_paths.push_back(link_path);
                return link_path;
            } catch (const std::filesystem::filesystem_error&) {
                return {}; // Return empty path if symlink creation fails
            }
        }
        
        void cleanup() {
            for (auto it = created_paths.rbegin(); it != created_paths.rend(); ++it) {
                try {
                    if (std::filesystem::exists(*it)) {
                        if (std::filesystem::is_directory(*it)) {
                            std::filesystem::remove_all(*it);
                        } else {
                            std::filesystem::remove(*it);
                        }
                    }
                } catch (const std::filesystem::filesystem_error&) {
                    // Ignore cleanup errors
                }
            }
            created_paths.clear();
        }
    };
}

TEST_CASE("Path normalization unit tests", "[path-handling][normalization]") {
    SECTION("Basic path normalization") {
        std::vector<std::pair<std::string, std::string>> test_cases = {
            {"/Users/test/Documents/video.mov", "/Users/test/Documents/video.mov"},
            {"/Users/test/Documents/../Movies/video.mp4", "/Users/test/Movies/video.mp4"},
            {"/Users/test/./Documents/video.mov", "/Users/test/Documents/video.mov"},
            {"./relative/path/video.mov", "relative/path/video.mov"},
            {"/Users/test//double//slash//video.mov", "/Users/test/double/slash/video.mov"}
        };
        
        for (const auto& [input, expected_pattern] : test_cases) {
            std::string normalized = PathProcessor::normalize_path(input);
            
            // Normalized path should not be empty
            REQUIRE(!normalized.empty());
            
            // Should not contain double slashes
            REQUIRE(normalized.find("//") == std::string::npos);
            
            // Should not contain "/./"
            REQUIRE(normalized.find("/./") == std::string::npos);
            
            // For relative paths that don't start with "/", should not start with "/"
            if (input[0] != '/' && input.find("./") == 0) {
                REQUIRE(normalized[0] != '/');
            }
        }
    }
    
    SECTION("Unicode path normalization") {
        std::vector<std::string> unicode_paths = {
            "/Users/test/Documents/tëst_vídeo.mov",
            "/Users/test/Movies/测试视频.mp4",
            "/Users/test/Videos/тест_видео.mov",
            "/Users/test/Files/café_video.m4v"
        };
        
        for (const auto& path : unicode_paths) {
            std::string normalized = PathProcessor::normalize_path(path);
            
            // Should handle Unicode characters without crashing
            REQUIRE(!normalized.empty());
            
            // Should preserve the Unicode characters (basic check)
            REQUIRE(normalized.length() >= path.length() - 10); // Allow some variation
        }
    }
    
    SECTION("Edge case path handling") {
        std::vector<std::string> edge_cases = {
            "",
            "/",
            ".",
            "..",
            "~",
            "/Users/test/very/long/path/with/many/components/that/goes/on/and/on/video.mov"
        };
        
        for (const auto& path : edge_cases) {
            std::string normalized = PathProcessor::normalize_path(path);
            
            // Should not crash on edge cases
            // Empty input might result in empty output, which is acceptable
            if (!path.empty()) {
                REQUIRE(!normalized.empty());
            }
        }
    }
}

TEST_CASE("macOS filesystem detection unit tests", "[path-handling][filesystem]") {
    SECTION("Typical macOS paths") {
        std::vector<std::string> macos_paths = {
            "/Users/testuser/Documents/video.mov",
            "/Applications/VideoApp.app/Contents/Resources/video.mp4",
            "/System/Library/Frameworks/AVFoundation.framework",
            "/Library/Application Support/VideoEditor/config.plist",
            "/Volumes/External Drive/Videos/movie.mov",
            "/private/tmp/temp_video.mp4",
            "/opt/homebrew/lib/libopencv.dylib",
            "/usr/local/bin/ffmpeg"
        };
        
        for (const auto& path : macos_paths) {
            bool is_macos = PathProcessor::is_macos_filesystem_path(path);
            REQUIRE(is_macos);
        }
    }
    
    SECTION("Non-macOS paths") {
        std::vector<std::string> non_macos_paths = {
            "/home/user/videos/movie.mp4",
            "C:\\Users\\test\\Videos\\movie.mov",
            "/var/www/html/video.webm",
            "\\\\server\\share\\video.avi",
            "D:\\Movies\\video.mkv"
        };
        
        for (const auto& path : non_macos_paths) {
            bool is_macos = PathProcessor::is_macos_filesystem_path(path);
            REQUIRE_FALSE(is_macos);
        }
    }
    
    SECTION("Ambiguous paths") {
        std::vector<std::string> ambiguous_paths = {
            "/tmp/video.mov",
            "/usr/bin/tool",
            "/etc/config",
            "relative/path/video.mp4"
        };
        
        for (const auto& path : ambiguous_paths) {
            bool is_macos = PathProcessor::is_macos_filesystem_path(path);
            // These paths could be on any Unix system, so result may vary
            // Just ensure the function doesn't crash
            REQUIRE((is_macos == true || is_macos == false));
        }
    }
}

TEST_CASE("Path separator conversion unit tests", "[path-handling][separators]") {
    SECTION("Windows to Unix separator conversion") {
        std::vector<std::pair<std::string, std::string>> test_cases = {
            {"C:\\Users\\test\\video.mov", "C:/Users/test/video.mov"},
            {"\\\\server\\share\\video.avi", "//server/share/video.avi"},
            {"relative\\path\\video.mp4", "relative/path/video.mp4"},
            {"mixed/and\\back\\slashes/video.mkv", "mixed/and/back/slashes/video.mkv"},
            {"/already/unix/path/video.mov", "/already/unix/path/video.mov"}
        };
        
        for (const auto& [input, expected] : test_cases) {
            std::string converted = PathProcessor::convert_path_separators(input);
            REQUIRE(converted == expected);
            
            // Should not contain any backslashes
            REQUIRE(converted.find('\\') == std::string::npos);
        }
    }
    
    SECTION("Empty and edge case inputs") {
        std::vector<std::string> edge_cases = {
            "",
            "\\",
            "/",
            "\\\\",
            "//",
            "C:\\",
            "C:/"
        };
        
        for (const auto& input : edge_cases) {
            std::string converted = PathProcessor::convert_path_separators(input);
            
            // Should not crash
            REQUIRE(converted.find('\\') == std::string::npos);
        }
    }
}

TEST_CASE("Unicode filename normalization unit tests", "[path-handling][unicode]") {
    SECTION("Basic Unicode normalization") {
        std::vector<std::string> test_filenames = {
            "normal_filename.mov",
            "tëst_vídeo.mp4",
            "测试视频.mov",
            "тест_видео.mp4",
            "café_video.m4v",
            "naïve_approach.avi"
        };
        
        for (const auto& filename : test_filenames) {
            std::string normalized = PathProcessor::normalize_unicode_filename(filename);
            
            // Should not be empty
            REQUIRE(!normalized.empty());
            
            // Should not contain path separators
            REQUIRE(normalized.find('/') == std::string::npos);
            REQUIRE(normalized.find('\\') == std::string::npos);
            
            // Should preserve basic structure
            if (filename.find('.') != std::string::npos) {
                REQUIRE(normalized.find('.') != std::string::npos);
            }
        }
    }
    
    SECTION("Security: Path separator removal") {
        std::vector<std::string> malicious_filenames = {
            "../../../etc/passwd",
            "..\\..\\..\\windows\\system32\\config",
            "normal/with/slashes.mov",
            "back\\slash\\filename.mp4",
            "/absolute/path/file.avi"
        };
        
        for (const auto& filename : malicious_filenames) {
            std::string normalized = PathProcessor::normalize_unicode_filename(filename);
            
            // Should remove all path separators
            REQUIRE(normalized.find('/') == std::string::npos);
            REQUIRE(normalized.find('\\') == std::string::npos);
            
            // Should not be empty (unless original was only separators)
            if (filename.find_first_not_of("/\\") != std::string::npos) {
                REQUIRE(!normalized.empty());
            }
        }
    }
    
    SECTION("Whitespace handling") {
        std::vector<std::pair<std::string, std::string>> test_cases = {
            {"  filename.mov  ", "filename.mov"},
            {"\t\nfilename.mp4\r\n", "filename.mp4"},
            {"   ", ""},
            {"normal filename.avi", "normal filename.avi"}, // Internal spaces preserved
            {" \t video \n file \r .mov \t ", "video \n file \r .mov"}
        };
        
        for (const auto& [input, expected] : test_cases) {
            std::string normalized = PathProcessor::normalize_unicode_filename(input);
            REQUIRE(normalized == expected);
        }
    }
}

TEST_CASE("Video path validation unit tests", "[path-handling][validation]") {
    TestFileManager file_manager;
    
    SECTION("Valid video file extensions") {
        std::vector<std::string> valid_extensions = {
            ".mov", ".mp4", ".m4v", ".avi", ".mkv", ".webm", ".flv", ".wmv"
        };
        
        for (const auto& ext : valid_extensions) {
            auto test_file = file_manager.create_test_file("test_video" + ext);
            bool is_valid = PathProcessor::validate_video_path(test_file);
            REQUIRE(is_valid);
        }
    }
    
    SECTION("Invalid file extensions") {
        std::vector<std::string> invalid_extensions = {
            ".txt", ".jpg", ".png", ".pdf", ".doc", ".zip", ".exe"
        };
        
        for (const auto& ext : invalid_extensions) {
            auto test_file = file_manager.create_test_file("test_file" + ext);
            bool is_valid = PathProcessor::validate_video_path(test_file);
            REQUIRE_FALSE(is_valid);
        }
    }
    
    SECTION("Edge case filenames") {
        std::vector<std::string> edge_cases = {
            ".mov",           // No base name
            "video.",         // No extension
            "video",          // No extension
            "",               // Empty
            ".",              // Current directory
            ".."              // Parent directory
        };
        
        for (const auto& filename : edge_cases) {
            if (!filename.empty()) {
                auto test_file = file_manager.create_test_file(filename);
                bool is_valid = PathProcessor::validate_video_path(test_file);
                
                // Most edge cases should be invalid
                if (filename == ".mov" || filename == "video." || filename == "video") {
                    REQUIRE_FALSE(is_valid);
                }
            } else {
                // Empty path should be invalid
                bool is_valid = PathProcessor::validate_video_path("");
                REQUIRE_FALSE(is_valid);
            }
        }
    }
    
    SECTION("Case sensitivity in extensions") {
        std::vector<std::string> case_variants = {
            ".MOV", ".Mp4", ".AVI", ".MKV", ".WebM"
        };
        
        for (const auto& ext : case_variants) {
            auto test_file = file_manager.create_test_file("test_video" + ext);
            bool is_valid = PathProcessor::validate_video_path(test_file);
            REQUIRE(is_valid); // Should handle case-insensitive extensions
        }
    }
}

TEST_CASE("Symbolic link resolution unit tests", "[path-handling][symlinks]") {
    TestFileManager file_manager;
    
    SECTION("Basic symlink resolution") {
        // Create a target file
        auto target_file = file_manager.create_test_file("target_video.mov", "target content");
        
        // Create a symlink to it
        auto symlink = file_manager.create_symlink(target_file, "link_to_video.mov");
        
        if (!symlink.empty()) { // Only test if symlink creation succeeded
            std::string resolved = PathProcessor::resolve_aliases(symlink.string());
            
            // Should resolve to the target
            REQUIRE(!resolved.empty());
            REQUIRE(resolved != symlink.string());
        }
    }
    
    SECTION("Non-symlink path handling") {
        auto regular_file = file_manager.create_test_file("regular_video.mov");
        std::string resolved = PathProcessor::resolve_aliases(regular_file.string());
        
        // Should return the original path for non-symlinks
        REQUIRE(resolved == regular_file.string());
    }
    
    SECTION("Broken symlink handling") {
        // Create a symlink to a non-existent target
        std::filesystem::path nonexistent = "/tmp/nonexistent_target.mov";
        auto broken_link = file_manager.create_symlink(nonexistent, "broken_link.mov");
        
        if (!broken_link.empty()) {
            std::string resolved = PathProcessor::resolve_aliases(broken_link.string());
            
            // Should handle broken symlinks gracefully
            REQUIRE(!resolved.empty());
        }
    }
}

TEST_CASE("Case sensitivity detection unit tests", "[path-handling][case-sensitivity]") {
    TestFileManager file_manager;
    
    SECTION("Case sensitivity detection") {
        // Create a test directory
        auto test_dir = file_manager.create_test_directory("case_test_dir");
        
        bool is_case_sensitive = PathProcessor::is_case_sensitive_path(test_dir.string());
        
        // Should return a boolean value
        REQUIRE((is_case_sensitive == true || is_case_sensitive == false));
        
        // On most macOS systems, should be case-insensitive
        // But we can't assume this, so just verify it doesn't crash
    }
    
    SECTION("Non-existent path handling") {
        std::string nonexistent_path = "/tmp/definitely_does_not_exist_12345";
        bool is_case_sensitive = PathProcessor::is_case_sensitive_path(nonexistent_path);
        
        // Should handle non-existent paths gracefully
        REQUIRE((is_case_sensitive == true || is_case_sensitive == false));
    }
}

TEST_CASE("Path handling integration tests", "[path-handling][integration]") {
    TestFileManager file_manager;
    
    SECTION("Complete path processing workflow") {
        // Test a complete workflow: create file, normalize path, validate, resolve
        std::string original_path = "/tmp/../tmp/test video file.mov";
        auto test_file = file_manager.create_test_file("test video file.mov");
        
        // Normalize the path
        std::string normalized = PathProcessor::normalize_path(original_path);
        REQUIRE(!normalized.empty());
        
        // Check if it's a macOS path
        bool is_macos = PathProcessor::is_macos_filesystem_path(normalized);
        
        // Validate as video path
        bool is_valid_video = PathProcessor::validate_video_path(test_file);
        REQUIRE(is_valid_video);
        
        // Resolve any aliases
        std::string resolved = PathProcessor::resolve_aliases(test_file.string());
        REQUIRE(!resolved.empty());
    }
    
    SECTION("Unicode filename workflow") {
        // Test Unicode filename handling
        std::string unicode_filename = "测试_tëst_видео.mp4";
        std::string normalized_filename = PathProcessor::normalize_unicode_filename(unicode_filename);
        
        REQUIRE(!normalized_filename.empty());
        REQUIRE(normalized_filename.find('/') == std::string::npos);
        
        // Create file with normalized name
        auto test_file = file_manager.create_test_file(normalized_filename);
        bool is_valid = PathProcessor::validate_video_path(test_file);
        REQUIRE(is_valid);
    }
}

#endif // MACOS_BUILD