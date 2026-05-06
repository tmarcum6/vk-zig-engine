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
    fprintf(stderr, "DEBUG: Entering imgui_wrapper_glfw_init, s_window=%p\n", s_window);
    
    // Create ImGui context
    ImGui::CreateContext();
    ImGuiIO& io = ImGui::GetIO();
    io.ConfigFlags |= ImGuiConfigFlags_NavEnableKeyboard;     // Enable Keyboard Controls
    io.ConfigFlags |= ImGuiConfigFlags_NavEnableGamepad;      // Enable Gamepad Controls
    
    fprintf(stderr, "DEBUG: GLFW window handle = %p\n", s_window);
    if (s_window) {
        fprintf(stderr, "DEBUG: Calling ImGui_ImplGlfw_InitForVulkan\n");
        bool init_result = ImGui_ImplGlfw_InitForVulkan(s_window, true);
        fprintf(stderr, "DEBUG: ImGui_ImplGlfw_InitForVulkan returned %d\n", init_result);
        
        if (init_result) {
            fprintf(stderr, "DEBUG: ImGui GLFW backend initialized\n");
            ImGuiViewport* viewport = ImGui::GetMainViewport();
            fprintf(stderr, "DEBUG: Viewport platform handle = %p\n", viewport->PlatformHandle);
        } else {
            fprintf(stderr, "ERROR: ImGui_ImplGlfw_InitForVulkan failed!\n");
        }
    } else {
        fprintf(stderr, "ERROR: GLFW window handle not set. Call imgui_wrapper_glfw_set_window() first!\n");
    }
}

void imgui_wrapper_glfw_shutdown() {
    if (s_window) {
        ImGui_ImplGlfw_Shutdown();
        fprintf(stderr, "DEBUG: GLFW backend shut down\n");
    }
    else {
        fprintf(stderr, "DEBUG: Skipping GLFW shutdown (no window set)\n");
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
    const VkAllocationCallbacks* allocator,
    void (*check_vk_result)(VkResult err)
) {
    fprintf(stderr, "DEBUG: ImGui Vulkan init (Instance=%p, PD=%p, Dev=%p, Queue=%p)\n",
            instance, physical_device, device, queue);
    
    // Set up Vulkan init info - use render pass (not dynamic rendering)
    ImGui_ImplVulkan_InitInfo init_info = {};
    init_info.ApiVersion = VK_API_VERSION_1_3;
    init_info.Instance = (VkInstance)instance;
    init_info.PhysicalDevice = (VkPhysicalDevice)physical_device;
    init_info.Device = (VkDevice)device;
    init_info.QueueFamily = queue_family;
    init_info.Queue = (VkQueue)queue;
    init_info.PipelineCache = (VkPipelineCache)pipeline_cache;
    init_info.DescriptorPool = (VkDescriptorPool)descriptor_pool;
    init_info.MinImageCount = min_image_count;
    init_info.ImageCount = image_count;
    
    // Use render pass (not dynamic rendering - avoids vkCmdBeginRenderingKHR issue)
    init_info.UseDynamicRendering = false;
    init_info.PipelineInfoMain.RenderPass = (VkRenderPass)render_pass;
    init_info.PipelineInfoMain.Subpass = 0;
    init_info.PipelineInfoMain.MSAASamples = msaa_samples;
    
    init_info.Allocator = allocator;
    init_info.CheckVkResultFn = check_vk_result;
    
    fprintf(stderr, "DEBUG: Calling ImGui_ImplVulkan_Init with render pass\n");
    bool result = ImGui_ImplVulkan_Init(&init_info);
    fprintf(stderr, "DEBUG: ImGui_ImplVulkan_Init returned %d\n", result);
    
    if (result) {
        s_vulkan_initialized = true;
        fprintf(stderr, "DEBUG: ImGui Vulkan backend initialized\n");
    } else {
        s_vulkan_initialized = false;
        fprintf(stderr, "ERROR: ImGui Vulkan backend init failed\n");
    }
}

void imgui_wrapper_vulkan_shutdown() {
    if (s_vulkan_initialized) {
        ImGui_ImplVulkan_Shutdown();
        ImGui::DestroyContext();
        fprintf(stderr, "DEBUG: Vulkan backend shut down\n");
    }
    else {
        fprintf(stderr, "DEBUG: Skipping Vulkan shutdown (vulkan not initialized with imgui)\n");
    }
    
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
    if (s_vulkan_initialized && command_buffer != nullptr) {
        // command_buffer is already a VkCommandBuffer (passed as void* from Zig)
        VkCommandBuffer cmd = (VkCommandBuffer)command_buffer;
        ImGui_ImplVulkan_RenderDrawData(ImGui::GetDrawData(), cmd, VK_NULL_HANDLE);
    }
}

void imgui_wrapper_vulkan_create_fonts_texture(imgui_vk_command_buffer command_buffer) {
    // Fonts texture is now created automatically in ImGui_ImplVulkan_Init()
    // This function is kept for API compatibility but does nothing
}
