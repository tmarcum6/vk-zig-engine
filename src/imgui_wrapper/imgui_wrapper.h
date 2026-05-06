#ifndef IMGUI_WRAPPER_H
#define IMGUI_WRAPPER_H

#include <vulkan/vulkan.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

// Vulkan handle types as void* to avoid opaque type mismatches
typedef void* imgui_vk_instance;
typedef void* imgui_vk_physical_device;
typedef void* imgui_vk_device;
typedef void* imgui_vk_queue;
typedef void* imgui_vk_pipeline_cache;
typedef void* imgui_vk_descriptor_pool;
typedef void* imgui_vk_render_pass;
typedef void* imgui_vk_command_buffer;

// Init/shutdown platform backend (GLFW)
void imgui_wrapper_glfw_set_window(void* window);
void imgui_wrapper_glfw_init();
void imgui_wrapper_glfw_shutdown();

// Init/shutdown renderer backend (Vulkan)
void imgui_wrapper_vulkan_init(
    imgui_vk_instance instance,
    imgui_vk_physical_device physical_device,
    imgui_vk_device device,
    uint32_t queue_family,
    imgui_vk_queue queue,
    imgui_vk_pipeline_cache pipeline_cache,
    imgui_vk_descriptor_pool descriptor_pool,
    uint32_t min_image_count,
    uint32_t image_count,
    imgui_vk_render_pass render_pass,
    VkSampleCountFlagBits msaa_samples,
    const VkAllocationCallbacks* allocator,
    void (*check_vk_result)(VkResult err)
);
void imgui_wrapper_vulkan_shutdown();
void imgui_wrapper_vulkan_set_min_image_count(uint32_t min_image_count);

// Per-frame functions
void imgui_wrapper_new_frame();
void imgui_wrapper_render(imgui_vk_command_buffer command_buffer);

// Fonts
void imgui_wrapper_vulkan_create_fonts_texture(imgui_vk_command_buffer command_buffer);

#ifdef __cplusplus
}
#endif

#endif // IMGUI_WRAPPER_H
