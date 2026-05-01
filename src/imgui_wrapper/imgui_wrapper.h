#ifndef IMGUI_WRAPPER_H
#define IMGUI_WRAPPER_H

#include <vulkan/vulkan.h>
#include <GLFW/glfw3.h>

#ifdef __cplusplus
extern "C" {
#endif

// Init/shutdown platform backend (GLFW)
void imgui_wrapper_glfw_init(GLFWwindow* window);
void imgui_wrapper_glfw_shutdown();

// Init/shutdown renderer backend (Vulkan)
void imgui_wrapper_vulkan_init(
    VkInstance instance,
    VkPhysicalDevice physical_device,
    VkDevice device,
    uint32_t queue_family,
    VkQueue queue,
    VkPipelineCache pipeline_cache,
    VkDescriptorPool descriptor_pool,
    uint32_t min_image_count,
    uint32_t image_count,
    VkRenderPass render_pass,
    VkSampleCountFlagBits msaa_samples,
    void* allocator,
    void (*check_vk_result)(VkResult err)
);
void imgui_wrapper_vulkan_shutdown();
void imgui_wrapper_vulkan_set_min_image_count(uint32_t min_image_count);

// Per-frame functions
void imgui_wrapper_new_frame();
void imgui_wrapper_render(VkCommandBuffer command_buffer);

// Fonts
void imgui_wrapper_vulkan_create_fonts_texture(VkCommandBuffer command_buffer);

#ifdef __cplusplus
}
#endif

#endif // IMGUI_WRAPPER_H
