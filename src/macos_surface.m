// src/macos_surface.m
// Objective-C helper to create Vulkan surface on macOS
#import <Cocoa/Cocoa.h>
#import <QuartzCore/QuartzCore.h>
#import <Metal/Metal.h>
#include <vulkan/vulkan.h>
#include <vulkan/vulkan_metal.h>
#include <stdio.h>

// Create Vulkan surface using CAMetalLayer
VkResult CreateMetalSurface(VkInstance instance, void* cocoaWindow, VkSurfaceKHR* surface) {
    if (!cocoaWindow) {
        fprintf(stderr, "CreateMetalSurface: Null cocoaWindow\n");
        return VK_ERROR_INITIALIZATION_FAILED;
    }
    
    NSWindow* nsWindow = (NSWindow*)cocoaWindow;
    
    // Get content view
    NSView* contentView = [nsWindow contentView];
    if (!contentView) {
        fprintf(stderr, "CreateMetalSurface: No content view\n");
        return VK_ERROR_INITIALIZATION_FAILED;
    }
    
    // Get or create CAMetalLayer
    CAMetalLayer* metalLayer = (CAMetalLayer*)[contentView layer];
    if (!metalLayer || ![metalLayer isKindOfClass:[CAMetalLayer class]]) {
        metalLayer = [CAMetalLayer layer];
        [contentView setLayer:metalLayer];
        [contentView setWantsLayer:YES];
    }
    
    if (!metalLayer) {
        fprintf(stderr, "CreateMetalSurface: Failed to get/create CAMetalLayer\n");
        return VK_ERROR_INITIALIZATION_FAILED;
    }
    
    fprintf(stderr, "DEBUG: Got CAMetalLayer: %p\n", metalLayer);
    
    // Load vkCreateMetalSurfaceEXT
    PFN_vkCreateMetalSurfaceEXT vkCreateMetalSurfaceEXT = 
        (PFN_vkCreateMetalSurfaceEXT)vkGetInstanceProcAddr(instance, "vkCreateMetalSurfaceEXT");
    
    if (!vkCreateMetalSurfaceEXT) {
        fprintf(stderr, "CreateMetalSurface: vkCreateMetalSurfaceEXT not found\n");
        return VK_ERROR_EXTENSION_NOT_PRESENT;
    }
    
    // Create surface
    VkMetalSurfaceCreateInfoEXT surfaceInfo;
    surfaceInfo.sType = VK_STRUCTURE_TYPE_METAL_SURFACE_CREATE_INFO_EXT;
    surfaceInfo.pNext = NULL;
    surfaceInfo.flags = 0;
    // Cast CAMetalLayer to void* for Vulkan
    surfaceInfo.pLayer = (const void*)metalLayer;
    
    VkResult result = vkCreateMetalSurfaceEXT(instance, &surfaceInfo, NULL, surface);
    fprintf(stderr, "DEBUG: vkCreateMetalSurfaceEXT result: %d, surface: %p\n", result, surface ? *surface : NULL);
    
    return result;
}
