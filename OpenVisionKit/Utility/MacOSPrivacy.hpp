/**
 * @file MacOSPrivacy.hpp
 * @brief macOS Privacy and Permission Handling for OpenVisionKit
 * 
 * This module provides utilities for handling macOS privacy permissions
 * including camera access, microphone access, and file system permissions.
 * 
 * **Feature: macos-build-support, Property 15: Security configuration compliance**
 * **Validates: Requirements 8.5**
 */

#ifndef OPENVISIONKIT_UTILITY_MACOSPRIVACY_HPP
#define OPENVISIONKIT_UTILITY_MACOSPRIVACY_HPP

#ifdef MACOS_BUILD

#include <string>
#include <functional>

namespace lvk {
namespace privacy {

/**
 * @brief Enumeration of macOS privacy permission types
 */
enum class PermissionType {
    Camera,           ///< Camera access permission
    Microphone,       ///< Microphone access permission
    ScreenCapture,    ///< Screen capture permission
    Accessibility,    ///< Accessibility permission
    FileAccess        ///< File system access permission
};

/**
 * @brief Enumeration of permission authorization status
 */
enum class AuthorizationStatus {
    NotDetermined,    ///< User has not yet been asked for permission
    Restricted,       ///< Permission is restricted by system policy
    Denied,           ///< User has denied permission
    Authorized        ///< User has granted permission
};

/**
 * @brief Callback type for permission request completion
 */
using PermissionCallback = std::function<void(AuthorizationStatus status)>;

/**
 * @brief Check the current authorization status for a permission type
 * 
 * @param type The type of permission to check
 * @return The current authorization status
 */
AuthorizationStatus checkPermissionStatus(PermissionType type);

/**
 * @brief Request permission from the user
 * 
 * This function will display a system dialog asking the user for permission
 * if the current status is NotDetermined. If permission has already been
 * granted or denied, the callback will be called immediately with the
 * current status.
 * 
 * @param type The type of permission to request
 * @param callback Callback to be called when the request completes
 */
void requestPermission(PermissionType type, PermissionCallback callback);

/**
 * @brief Check if a permission is available on the current macOS version
 * 
 * Some permissions are only available on certain macOS versions.
 * 
 * @param type The type of permission to check
 * @return true if the permission type is available, false otherwise
 */
bool isPermissionAvailable(PermissionType type);

/**
 * @brief Get a human-readable description of a permission type
 * 
 * @param type The type of permission
 * @return A string describing the permission
 */
std::string getPermissionDescription(PermissionType type);

/**
 * @brief Get the usage description key for Info.plist
 * 
 * Returns the key that should be used in Info.plist to provide
 * a usage description for the permission.
 * 
 * @param type The type of permission
 * @return The Info.plist key for the usage description
 */
std::string getUsageDescriptionKey(PermissionType type);

/**
 * @brief Open System Preferences to the relevant privacy settings
 * 
 * This function opens System Preferences (or System Settings on macOS 13+)
 * to the appropriate privacy settings pane for the given permission type.
 * 
 * @param type The type of permission
 * @return true if the settings were opened successfully, false otherwise
 */
bool openPrivacySettings(PermissionType type);

/**
 * @brief RAII wrapper for permission-protected operations
 * 
 * This class provides a convenient way to check permissions before
 * performing operations that require them.
 */
class PermissionGuard {
public:
    /**
     * @brief Construct a permission guard
     * 
     * @param type The type of permission required
     */
    explicit PermissionGuard(PermissionType type);
    
    /**
     * @brief Check if the required permission is granted
     * 
     * @return true if permission is granted, false otherwise
     */
    bool isAuthorized() const;
    
    /**
     * @brief Get the current authorization status
     * 
     * @return The current authorization status
     */
    AuthorizationStatus status() const;
    
    /**
     * @brief Request permission if not already determined
     * 
     * @param callback Callback to be called when the request completes
     */
    void requestIfNeeded(PermissionCallback callback);
    
private:
    PermissionType m_type;
    AuthorizationStatus m_status;
};

/**
 * @brief Privacy manifest information for App Store compliance
 * 
 * This structure contains information required for Apple's privacy
 * manifest requirements (introduced in iOS 17 / macOS 14).
 */
struct PrivacyManifest {
    std::string trackingDomains;      ///< Domains used for tracking (empty if none)
    std::string collectedDataTypes;   ///< Types of data collected
    std::string dataUsePurposes;      ///< Purposes for data use
    bool usesTracking;                ///< Whether the app uses tracking
    
    /**
     * @brief Generate privacy manifest content for PrivacyInfo.xcprivacy
     * 
     * @return The privacy manifest content as a string
     */
    std::string generateManifest() const;
};

/**
 * @brief Get the default privacy manifest for OpenVisionKit
 * 
 * Returns a privacy manifest configured for typical video processing
 * use cases without tracking or data collection.
 * 
 * @return The default privacy manifest
 */
PrivacyManifest getDefaultPrivacyManifest();

} // namespace privacy
} // namespace lvk

#endif // MACOS_BUILD

#endif // OPENVISIONKIT_UTILITY_MACOSPRIVACY_HPP
