#include "imgui_wrapper.h"

// Include ImGui core and backends (C++ API directly)
#include "../imgui_impl/imgui_impl_glfw.h"
#include "../imgui_impl/imgui_impl_vulkan.h"

// Include ImGui headers for C++ API
#include <imgui.h>

void imgui_wrapper_glfw_init(GLFWwindow* window) {
    ImGui_ImplGlfw_InitForVulkan(window, true);
}

void imgui_wrapper_glfw_shutdown() {
    ImGui_ImplGlfw_Shutdown();
}

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
) {
    ImGui_ImplVulkan_InitInfo init_info;
    memset(&init_info, 0, sizeof(init_info));
    
    init_info.Instance = instance;
    init_info.PhysicalDevice = physical_device;
    init_info.Device = device;
    init_info.QueueFamily = queue_family;
    init_info.Queue = queue;
    init_info.PipelineCache = pipeline_cache;
    init_info.DescriptorPool = descriptor_pool;
    init_info.MinImageCount = min_image_count;
    init_info.ImageCount = image_count;
    init_info.PipelineInfoMain.RenderPass = render_pass;
    init_info.PipelineInfoMain.MSAASamples = msaa_samples;
    init_info.Allocator = (const VkAllocationCallbacks*)allocator;
    init_info.CheckVkResultFn = check_vk_result;
    
    ImGui_ImplVulkan_Init(&init_info);
}

void imgui_wrapper_vulkan_shutdown() {
    ImGui_ImplVulkan_Shutdown();
}

void imgui_wrapper_vulkan_set_min_image_count(uint32_t min_image_count) {
    ImGui_ImplVulkan_SetMinImageCount(min_image_count);
}

void imgui_wrapper_new_frame() {
    ImGui_ImplGlfw_NewFrame();
    ImGui_ImplVulkan_NewFrame();
    ImGui::NewFrame();
}

void imgui_wrapper_render(VkCommandBuffer command_buffer) {
    ImGui::Render();
    ImGui_ImplVulkan_RenderDrawData(ImGui::GetDrawData(), command_buffer, VK_NULL_HANDLE);
}

void imgui_wrapper_vulkan_create_fonts_texture(VkCommandBuffer command_buffer) {
    // Fonts texture is now created automatically in ImGui_ImplVulkan_Init()
    // This function is kept for API compatibility but does nothing
}

