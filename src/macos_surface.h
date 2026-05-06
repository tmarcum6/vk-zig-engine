// src/macos_surface.h
// C-linkage header for macOS Metal surface creation

#ifndef MACOS_SURFACE_H
#define MACOS_SURFACE_H

#include <vulkan/vulkan.h>

#ifdef __cplusplus
extern "C" {
#endif

// Create Vulkan surface using CAMetalLayer
// This bypasses GLFW's problematic surface creation on macOS
VkResult CreateMetalSurface(VkInstance instance, void* cocoaWindow, VkSurfaceKHR* surface);

#ifdef __cplusplus
}
#endif

#endif // MACOS_SURFACE_H
