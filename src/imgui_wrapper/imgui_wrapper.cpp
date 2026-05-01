#include "imgui_wrapper.h"

// Include ImGui core and backends (C++ API directly)
#include "../imgui_impl/imgui_impl_glfw.h"
#include "../imgui_impl/imgui_impl_vulkan.h"

// Include ImGui headers for C++ API
#include <imgui.h>

// GLFW headers to get native window handle
#include <GLFW/glfw3.h>
#include <GLFW/glfw3native.h>

// Vulkan headers
#include <vulkan/vulkan.h>

// Standard I/O
#include <stdio.h>

// Store the window handle internally
static GLFWwindow* s_window = nullptr;
static bool s_vulkan_initialized = false;

void imgui_wrapper_glfw_set_window(void* window) {
    s_window = (GLFWwindow*)window;
}

void imgui_wrapper_glfw_init() {
    // Create ImGui context
    ImGui::CreateContext();
    ImGuiIO& io = ImGui::GetIO();
    io.ConfigFlags |= ImGuiConfigFlags_NavEnableKeyboard;     // Enable Keyboard Controls
    io.ConfigFlags |= ImGuiConfigFlags_NavEnableGamepad;      // Enable Gamepad Controls
    
    fprintf(stderr, "DEBUG: GLFW window handle = %p\n", s_window);
    if (s_window) {
        ImGui_ImplGlfw_InitForVulkan(s_window, true);
        fprintf(stderr, "DEBUG: ImGui GLFW backend initialized\n");
    } else {
        fprintf(stderr, "ERROR: GLFW window handle not set. Call imgui_wrapper_glfw_set_window() first!\n");
    }
}

void imgui_wrapper_glfw_shutdown() {
    if (s_window) {
        fprintf(stderr, "DEBUG: Shutting down GLFW backend\n");
        ImGui_ImplGlfw_Shutdown();
    }
}

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
    void* allocator,
    void (*check_vk_result)(VkResult err)
) {
    // DISABLED: Vulkan handle casting issue with MoltenVK
    // TODO: Debug why vkGetPhysicalDeviceProperties crashes
    fprintf(stderr, "DEBUG: Skipping ImGui Vulkan init (Instance=%p, PD=%p, Dev=%p)\n",
            instance, physical_device, device);
    (void)instance; (void)physical_device; (void)device; (void)queue_family;
    (void)queue; (void)pipeline_cache; (void)descriptor_pool;
    (void)min_image_count; (void)image_count; (void)render_pass;
    (void)msaa_samples; (void)allocator; (void)check_vk_result;
    s_vulkan_initialized = false;
}

void imgui_wrapper_vulkan_shutdown() {
    if (s_vulkan_initialized) {
        ImGui_ImplVulkan_Shutdown();
    }
    ImGui_ImplGlfw_Shutdown();
    ImGui::DestroyContext();
}

void imgui_wrapper_vulkan_set_min_image_count(uint32_t min_image_count) {
    ImGui_ImplVulkan_SetMinImageCount(min_image_count);
}

void imgui_wrapper_new_frame() {
    ImGui_ImplGlfw_NewFrame();
    if (s_vulkan_initialized) {
        ImGui_ImplVulkan_NewFrame();
    } else {
        // Build font atlas manually when Vulkan backend is disabled
        ImGuiIO& io = ImGui::GetIO();
        if (io.Fonts->TexIsBuilt == false) {
            unsigned char* pixels;
            int width, height;
            io.Fonts->GetTexDataAsRGBA32(&pixels, &width, &height);
            // In a real implementation, you'd upload this to a texture
            // For now, just mark it as built
            io.Fonts->TexIsBuilt = true;
        }
    }
    ImGui::NewFrame();
}

void imgui_wrapper_render(imgui_vk_command_buffer command_buffer) {
    ImGui::Render();
    if (s_vulkan_initialized) {
        ImGui_ImplVulkan_RenderDrawData(ImGui::GetDrawData(), *(VkCommandBuffer*)&command_buffer, VK_NULL_HANDLE);
    }
}

void imgui_wrapper_vulkan_create_fonts_texture(imgui_vk_command_buffer command_buffer) {
    // Fonts texture is now created automatically in ImGui_ImplVulkan_Init()
    // This function is kept for API compatibility but does nothing
}

