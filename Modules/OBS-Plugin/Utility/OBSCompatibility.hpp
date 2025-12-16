/**
 * OBS Studio Version Compatibility Layer
 * 
 * This header provides compatibility shims for different OBS Studio versions,
 * particularly for macOS-specific functionality.
 */

#pragma once

#include <obs.h>
#include <obs-module.h>

// Version detection macros
#ifndef OBS_VERSION_30_PLUS
    #define OBS_VERSION_30_PLUS 0
#endif

#ifndef OBS_VERSION_29_1_PLUS
    #define OBS_VERSION_29_1_PLUS 0
#endif

#ifndef OBS_MACOS_METAL_SUPPORT
    #define OBS_MACOS_METAL_SUPPORT 0
#endif

namespace LVK {
namespace OBSCompat {

/**
 * Graphics API compatibility layer
 */
class GraphicsAPI {
public:
    enum class Type {
        OPENGL,
        METAL,
        DIRECT3D11,
        VULKAN
    };
    
    /**
     * Get the current graphics API being used by OBS
     */
    static Type getCurrentAPI() {
#ifdef __APPLE__
        #if OBS_MACOS_METAL_SUPPORT
            // OBS 30+ on macOS may use Metal
            gs_device_t* device = obs_get_video_device();
            if (device) {
                // In a real implementation, this would check the actual device type
                // For now, assume Metal is available on macOS with OBS 30+
                return Type::METAL;
            }
        #endif
        // Fallback to OpenGL on macOS
        return Type::OPENGL;
#elif defined(_WIN32)
        return Type::DIRECT3D11;
#else
        return Type::OPENGL;
#endif
    }
    
    /**
     * Check if Metal is supported and available
     */
    static bool isMetalSupported() {
#ifdef __APPLE__
        #if OBS_MACOS_METAL_SUPPORT
            return true;
        #else
            return false;
        #endif
#else
        return false;
#endif
    }
};

/**
 * Plugin metadata compatibility
 */
class PluginMetadata {
public:
    /**
     * Get plugin metadata in format compatible with current OBS version
     */
    static const char* getPluginName() {
        return "OpenVisionKit OBS Plugin";
    }
    
    static const char* getPluginVersion() {
        return VERSION; // Defined by CMake
    }
    
    static const char* getPluginDescription() {
        return "Real-time video processing filters for OBS Studio";
    }
    
    /**
     * Get minimum OBS version requirement
     */
    static const char* getMinOBSVersion() {
        return "29.0.0";
    }
    
    /**
     * Check if current OBS version is supported
     */
    static bool isOBSVersionSupported() {
        // This would be implemented with actual version checking
        // For now, assume compatibility if we got this far
        return true;
    }
};

/**
 * Source/Filter registration compatibility
 */
class SourceRegistration {
public:
    /**
     * Register a source with version-appropriate parameters
     */
    template<typename SourceInfo>
    static void registerSource(SourceInfo& info) {
        #if OBS_VERSION_30_PLUS
            // OBS 30+ may have additional fields or requirements
            // Ensure all required fields are set
            if (!info.get_defaults) {
                info.get_defaults = nullptr;
            }
        #endif
        
        obs_register_source(&info);
    }
};

/**
 * Property handling compatibility
 */
class PropertyCompat {
public:
    /**
     * Create properties with version-appropriate settings
     */
    static obs_properties_t* createProperties() {
        obs_properties_t* props = obs_properties_create();
        
        #if OBS_VERSION_30_PLUS
            // OBS 30+ may have additional property features
            // Set any new default behaviors here
        #endif
        
        return props;
    }
    
    /**
     * Add property with compatibility handling
     */
    static obs_property_t* addFloatSlider(obs_properties_t* props, 
                                        const char* name, 
                                        const char* description,
                                        double min, double max, double step) {
        #if OBS_VERSION_29_1_PLUS
            // Use newer API if available
            return obs_properties_add_float_slider(props, name, description, min, max, step);
        #else
            // Fallback for older versions
            obs_property_t* prop = obs_properties_add_float(props, name, description, min, max, step);
            obs_property_float_set_slider(prop, true);
            return prop;
        #endif
    }
};

/**
 * macOS-specific compatibility helpers
 */
#ifdef __APPLE__
class MacOSCompat {
public:
    /**
     * Handle macOS-specific initialization
     */
    static bool initializeMacOSFeatures() {
        #if OBS_MACOS_METAL_SUPPORT
            // Initialize Metal support if available
            return initializeMetalSupport();
        #else
            // Initialize OpenGL support
            return initializeOpenGLSupport();
        #endif
    }
    
    /**
     * Handle macOS bundle path resolution
     */
    static std::string getPluginDataPath() {
        // Get the plugin bundle path
        // In a real implementation, this would use NSBundle or similar
        return "Contents/Resources";
    }
    
private:
    static bool initializeMetalSupport() {
        // Metal initialization code would go here
        return true;
    }
    
    static bool initializeOpenGLSupport() {
        // OpenGL initialization code would go here
        return true;
    }
};
#endif

} // namespace OBSCompat
} // namespace LVK