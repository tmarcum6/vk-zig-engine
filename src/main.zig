const std = @import("std");
const glfw = @import("glfw");
const vulkan_c = @import("vulkan_c");
const imgui = @import("imgui");
const imgui_wrapper = @import("imgui_wrapper");

extern fn glfwGetInstanceProcAddress(instance: vulkan_c.VkInstance, procname: [*c]const u8) ?*const anyopaque;
extern fn glfwCreateWindowSurface(instance: vulkan_c.VkInstance, window: ?*anyopaque, allocator: ?*const anyopaque, surface: *vulkan_c.VkSurfaceKHR) vulkan_c.VkResult;

fn loadVulkanFunc(comptime T: type, instance: vulkan_c.VkInstance, name: [*c]const u8) T {
    const func = glfwGetInstanceProcAddress(instance, name);
    return @ptrCast(@alignCast(func));
}

pub fn main() !void {
    var gpa = std.heap.DebugAllocator(.{}){};
    const allocator = gpa.allocator();
    defer _ = gpa.deinit();

    if (glfw.glfwInit() == 0) {
        std.debug.print("Failed to initialize GLFW\n", .{});
        return error.GlfwInitFailed;
    }
    defer glfw.glfwTerminate();

    if (glfw.glfwVulkanSupported() == 0) {
        std.debug.print("Vulkan not supported by GLFW\n", .{});
        return error.VulkanNotSupported;
    }

    glfw.glfwWindowHint(glfw.GLFW_CLIENT_API, glfw.GLFW_NO_API);

    const window = glfw.glfwCreateWindow(800, 600, "VK Zig Engine", null, null) orelse {
        std.debug.print("Failed to create window\n", .{});
        return error.WindowCreationFailed;
    };
    defer glfw.glfwDestroyWindow(window);

    var ext_count: u32 = 0;
    const extensions = glfw.glfwGetRequiredInstanceExtensions(&ext_count);
    std.debug.print("Required extensions count: {}\n", .{ext_count});
    for (extensions[0..ext_count]) |ext| {
        std.debug.print("  Extension: {s}\n", .{std.mem.span(ext)});
    }

    // Create Vulkan instance
    const app_info = vulkan_c.VkApplicationInfo{
        .sType = vulkan_c.VK_STRUCTURE_TYPE_APPLICATION_INFO,
        .pApplicationName = "VK Zig Engine",
        .applicationVersion = (@as(u32, 1) << 22) | (@as(u32, 0) << 12),
        .apiVersion = (@as(u32, 1) << 22) | (@as(u32, 0) << 12), // Vulkan 1.0
    };

    const instance_create_info = vulkan_c.VkInstanceCreateInfo{
        .sType = vulkan_c.VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO,
        .pApplicationInfo = &app_info,
        .enabledExtensionCount = @intCast(ext_count),
        .ppEnabledExtensionNames = extensions,
    };

    // Load vkCreateInstance function
    const CreateInstanceFn = *const fn (
        [*c]const vulkan_c.VkInstanceCreateInfo,
        ?*const vulkan_c.VkAllocationCallbacks,
        *vulkan_c.VkInstance,
    ) callconv(std.builtin.CallingConvention.c) vulkan_c.VkResult;

    const vkCreateInstance: CreateInstanceFn = loadVulkanFunc(CreateInstanceFn, null, "vkCreateInstance");

    var instance: vulkan_c.VkInstance = undefined;
    if (vkCreateInstance(&instance_create_info, null, &instance) != vulkan_c.VK_SUCCESS) {
        std.debug.print("Failed to create Vulkan instance\n", .{});
        return error.InstanceFailed;
    }
    defer {
        const DestroyInstanceFn = *const fn (vulkan_c.VkInstance, ?*const vulkan_c.VkAllocationCallbacks) callconv(std.builtin.CallingConvention.c) void;
        const vkDestroyInstance: DestroyInstanceFn =
            loadVulkanFunc(DestroyInstanceFn, instance, "vkDestroyInstance");
        vkDestroyInstance(instance, null);
    }

    // Create Vulkan surface using GLFW
    var surface: vulkan_c.VkSurfaceKHR = undefined;
    const surface_result = glfwCreateWindowSurface(
        instance,
        window,
        null,
        &surface,
    );
    if (surface_result != vulkan_c.VK_SUCCESS) {
        std.debug.print("Failed to create Vulkan surface: {}\n", .{surface_result});
        return error.SurfaceFailed;
    }
    defer {
        const DestroySurfaceFn = *const fn (vulkan_c.VkInstance, vulkan_c.VkSurfaceKHR, ?*const vulkan_c.VkAllocationCallbacks) callconv(std.builtin.CallingConvention.c) void;
        const vkDestroySurfaceKHR: DestroySurfaceFn =
            loadVulkanFunc(DestroySurfaceFn, instance, "vkDestroySurfaceKHR");
        vkDestroySurfaceKHR(instance, surface, null);
    }

    std.debug.print("Vulkan instance and surface created successfully!\n", .{});

    // Physical device selection
    const EnumeratePhysicalDevicesFn = *const fn (
        vulkan_c.VkInstance,
        *u32,
        ?[*]vulkan_c.VkPhysicalDevice,
    ) callconv(std.builtin.CallingConvention.c) vulkan_c.VkResult;

    const GetPhysicalDeviceQueueFamilyPropertiesFn = *const fn (
        vulkan_c.VkPhysicalDevice,
        *u32,
        ?[*]vulkan_c.VkQueueFamilyProperties,
    ) callconv(std.builtin.CallingConvention.c) void;

    const GetPhysicalDeviceSurfaceSupportKHRFn = *const fn (
        vulkan_c.VkPhysicalDevice,
        u32,
        vulkan_c.VkSurfaceKHR,
        *vulkan_c.VkBool32,
    ) callconv(std.builtin.CallingConvention.c) vulkan_c.VkResult;

    const vkEnumeratePhysicalDevices: EnumeratePhysicalDevicesFn =
        loadVulkanFunc(EnumeratePhysicalDevicesFn, instance, "vkEnumeratePhysicalDevices");

    const vkGetPhysicalDeviceQueueFamilyProperties: GetPhysicalDeviceQueueFamilyPropertiesFn =
        loadVulkanFunc(GetPhysicalDeviceQueueFamilyPropertiesFn, instance, "vkGetPhysicalDeviceQueueFamilyProperties");

    const vkGetPhysicalDeviceSurfaceSupportKHR: GetPhysicalDeviceSurfaceSupportKHRFn =
        loadVulkanFunc(GetPhysicalDeviceSurfaceSupportKHRFn, instance, "vkGetPhysicalDeviceSurfaceSupportKHR");

    // Get physical device count
    var device_count: u32 = 0;
    if (vkEnumeratePhysicalDevices(instance, &device_count, null) != vulkan_c.VK_SUCCESS) {
        std.debug.print("Failed to enumerate physical devices\n", .{});
        return error.EnumerateDevicesFailed;
    }

    if (device_count == 0) {
        std.debug.print("No Vulkan-compatible physical devices found\n", .{});
        return error.NoSuitableDevice;
    }

    // Allocate and get physical devices
    const physical_devices = try allocator.alloc(vulkan_c.VkPhysicalDevice, device_count);
    defer allocator.free(physical_devices);

    if (vkEnumeratePhysicalDevices(instance, &device_count, physical_devices.ptr) != vulkan_c.VK_SUCCESS) {
        std.debug.print("Failed to get physical devices\n", .{});
        return error.GetDevicesFailed;
    }

    // Find suitable physical device
    var selected_device: vulkan_c.VkPhysicalDevice = undefined;
    var graphics_family: u32 = std.math.maxInt(u32);
    var present_family: u32 = std.math.maxInt(u32);
    var device_found = false;

    for (physical_devices) |device| {
        // Per-device variables to avoid cross-device contamination
        var g_family: u32 = std.math.maxInt(u32);
        var p_family: u32 = std.math.maxInt(u32);

        // Get queue family count
        var queue_family_count: u32 = 0;
        vkGetPhysicalDeviceQueueFamilyProperties(device, &queue_family_count, null);

        if (queue_family_count == 0) continue;

        // Allocate and get queue family properties
        const queue_families = try allocator.alloc(vulkan_c.VkQueueFamilyProperties, queue_family_count);
        defer allocator.free(queue_families);
        vkGetPhysicalDeviceQueueFamilyProperties(device, &queue_family_count, queue_families.ptr);

        // Check each queue family for this device only
        for (queue_families, 0..) |props, i| {
            const family_idx: u32 = @intCast(i);

            // Check for graphics support
            if (props.queueFlags & vulkan_c.VK_QUEUE_GRAPHICS_BIT != 0) {
                if (g_family == std.math.maxInt(u32)) {
                    g_family = family_idx;
                }
            }

            // Check for present support
            var present_support: vulkan_c.VkBool32 = 0;
            if (vkGetPhysicalDeviceSurfaceSupportKHR(device, family_idx, surface, &present_support) == vulkan_c.VK_SUCCESS) {
                if (present_support != 0 and p_family == std.math.maxInt(u32)) {
                    p_family = family_idx;
                }
            }
        }

        // If this device has both graphics and present support, select it
        if (g_family != std.math.maxInt(u32) and p_family != std.math.maxInt(u32)) {
            graphics_family = g_family;
            present_family = p_family;
            selected_device = device;
            device_found = true;
            break;
        }
    }

    if (!device_found) {
        std.debug.print("No suitable physical device found (needs graphics + present support)\n", .{});
        return error.NoSuitableDevice;
    }

    std.debug.print("Selected physical device with graphics family: {}, present family: {}\n", .{ graphics_family, present_family });

    // Logical device creation
    const CreateDeviceFn = *const fn (
        vulkan_c.VkPhysicalDevice,
        [*c]const vulkan_c.VkDeviceCreateInfo,
        ?*const vulkan_c.VkAllocationCallbacks,
        *vulkan_c.VkDevice,
    ) callconv(std.builtin.CallingConvention.c) vulkan_c.VkResult;

    const GetDeviceQueueFn = *const fn (
        vulkan_c.VkDevice,
        u32,
        u32,
        *vulkan_c.VkQueue,
    ) callconv(std.builtin.CallingConvention.c) void;

    const EnumerateDeviceExtensionPropertiesFn = *const fn (
        vulkan_c.VkPhysicalDevice,
        ?[*:0]const u8,
        *u32,
        ?[*]vulkan_c.VkExtensionProperties,
    ) callconv(std.builtin.CallingConvention.c) vulkan_c.VkResult;

    const DestroyDeviceFn = *const fn (
        vulkan_c.VkDevice,
        ?*const vulkan_c.VkAllocationCallbacks,
    ) callconv(std.builtin.CallingConvention.c) void;

    const vkCreateDevice: CreateDeviceFn =
        loadVulkanFunc(CreateDeviceFn, instance, "vkCreateDevice");

    const vkGetDeviceQueue: GetDeviceQueueFn =
        loadVulkanFunc(GetDeviceQueueFn, instance, "vkGetDeviceQueue");

    const vkEnumerateDeviceExtensionProperties: EnumerateDeviceExtensionPropertiesFn =
        loadVulkanFunc(EnumerateDeviceExtensionPropertiesFn, instance, "vkEnumerateDeviceExtensionProperties");

    const vkDestroyDevice: DestroyDeviceFn =
        loadVulkanFunc(DestroyDeviceFn, instance, "vkDestroyDevice");

    // Check for swapchain extension support
    var extension_count: u32 = 0;
    if (vkEnumerateDeviceExtensionProperties(selected_device, null, &extension_count, null) != vulkan_c.VK_SUCCESS) {
        std.debug.print("Failed to enumerate device extensions\n", .{});
        return error.EnumerateExtensionsFailed;
    }

    const device_extensions = try allocator.alloc(vulkan_c.VkExtensionProperties, extension_count);
    defer allocator.free(device_extensions);

    if (vkEnumerateDeviceExtensionProperties(selected_device, null, &extension_count, device_extensions.ptr) != vulkan_c.VK_SUCCESS) {
        std.debug.print("Failed to get device extensions\n", .{});
        return error.GetExtensionsFailed;
    }

    const swapchain_extension = "VK_KHR_swapchain";
    var swapchain_supported = false;
    for (device_extensions) |ext| {
        const raw_name: [*c]const u8 = @ptrCast(&ext.extensionName);
        const name = std.mem.span(raw_name);
        if (std.mem.eql(u8, name, swapchain_extension)) {
            swapchain_supported = true;
            break;
        }
    }

    if (!swapchain_supported) {
        std.debug.print("VK_KHR_swapchain extension not supported\n", .{});
        return error.SwapchainNotSupported;
    }
    std.debug.print("VK_KHR_swapchain extension supported\n", .{});

    // Create queues - handle case where graphics and present are same family
    const same_family = graphics_family == present_family;
    const queue_count: u32 = if (same_family) 1 else 2;
    const queue_priority: f32 = 1.0;

    // Allocate queue create infos
    const queue_create_infos = try allocator.alloc(vulkan_c.VkDeviceQueueCreateInfo, queue_count);
    defer allocator.free(queue_create_infos);

    queue_create_infos[0] = vulkan_c.VkDeviceQueueCreateInfo{
        .sType = vulkan_c.VK_STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO,
        .queueFamilyIndex = graphics_family,
        .queueCount = 1,
        .pQueuePriorities = &queue_priority,
    };

    if (!same_family) {
        queue_create_infos[1] = vulkan_c.VkDeviceQueueCreateInfo{
            .sType = vulkan_c.VK_STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO,
            .queueFamilyIndex = present_family,
            .queueCount = 1,
            .pQueuePriorities = &queue_priority,
        };
    }

    // Device extensions to enable
    const enabled_extensions = [_][*c]const u8{swapchain_extension ++ "\x00"};

    const device_create_info = vulkan_c.VkDeviceCreateInfo{
        .sType = vulkan_c.VK_STRUCTURE_TYPE_DEVICE_CREATE_INFO,
        .queueCreateInfoCount = @intCast(queue_count),
        .pQueueCreateInfos = &queue_create_infos[0],
        .enabledExtensionCount = 1,
        .ppEnabledExtensionNames = &enabled_extensions[0],
    };

    var device: vulkan_c.VkDevice = undefined;
    if (vkCreateDevice(selected_device, &device_create_info, null, &device) != vulkan_c.VK_SUCCESS) {
        std.debug.print("Failed to create logical device\n", .{});
        return error.DeviceCreationFailed;
    }
    defer vkDestroyDevice(device, null);

    // Get queue handles
    var graphics_queue: vulkan_c.VkQueue = undefined;
    var present_queue: vulkan_c.VkQueue = undefined;
    vkGetDeviceQueue(device, graphics_family, 0, &graphics_queue);
    vkGetDeviceQueue(device, present_family, 0, &present_queue);

    std.debug.print("Logical device created successfully\n", .{});

    // Swapchain creation
    const GetPhysicalDeviceSurfaceCapabilitiesKHRFn = *const fn (
        vulkan_c.VkPhysicalDevice,
        vulkan_c.VkSurfaceKHR,
        *vulkan_c.VkSurfaceCapabilitiesKHR,
    ) callconv(std.builtin.CallingConvention.c) vulkan_c.VkResult;

    const GetPhysicalDeviceSurfaceFormatsKHRFn = *const fn (
        vulkan_c.VkPhysicalDevice,
        vulkan_c.VkSurfaceKHR,
        *u32,
        ?[*]vulkan_c.VkSurfaceFormatKHR,
    ) callconv(std.builtin.CallingConvention.c) vulkan_c.VkResult;

    const GetPhysicalDeviceSurfacePresentModesKHRFn = *const fn (
        vulkan_c.VkPhysicalDevice,
        vulkan_c.VkSurfaceKHR,
        *u32,
        ?[*]vulkan_c.VkPresentModeKHR,
    ) callconv(std.builtin.CallingConvention.c) vulkan_c.VkResult;

    const CreateSwapchainKHRFn = *const fn (
        vulkan_c.VkDevice,
        [*c]const vulkan_c.VkSwapchainCreateInfoKHR,
        ?*const vulkan_c.VkAllocationCallbacks,
        *vulkan_c.VkSwapchainKHR,
    ) callconv(std.builtin.CallingConvention.c) vulkan_c.VkResult;

    const DestroySwapchainKHRFn = *const fn (
        vulkan_c.VkDevice,
        vulkan_c.VkSwapchainKHR,
        ?*const vulkan_c.VkAllocationCallbacks,
    ) callconv(std.builtin.CallingConvention.c) void;

    const GetSwapchainImagesKHRFn = *const fn (
        vulkan_c.VkDevice,
        vulkan_c.VkSwapchainKHR,
        *u32,
        ?[*]vulkan_c.VkImage,
    ) callconv(std.builtin.CallingConvention.c) vulkan_c.VkResult;

    const CreateImageViewFn = *const fn (
        vulkan_c.VkDevice,
        [*c]const vulkan_c.VkImageViewCreateInfo,
        ?*const vulkan_c.VkAllocationCallbacks,
        *vulkan_c.VkImageView,
    ) callconv(std.builtin.CallingConvention.c) vulkan_c.VkResult;

    const DestroyImageViewFn = *const fn (
        vulkan_c.VkDevice,
        vulkan_c.VkImageView,
        ?*const vulkan_c.VkAllocationCallbacks,
    ) callconv(std.builtin.CallingConvention.c) void;

    const vkGetPhysicalDeviceSurfaceCapabilitiesKHR: GetPhysicalDeviceSurfaceCapabilitiesKHRFn =
        loadVulkanFunc(GetPhysicalDeviceSurfaceCapabilitiesKHRFn, instance, "vkGetPhysicalDeviceSurfaceCapabilitiesKHR");

    const vkGetPhysicalDeviceSurfaceFormatsKHR: GetPhysicalDeviceSurfaceFormatsKHRFn =
        loadVulkanFunc(GetPhysicalDeviceSurfaceFormatsKHRFn, instance, "vkGetPhysicalDeviceSurfaceFormatsKHR");

    const vkGetPhysicalDeviceSurfacePresentModesKHR: GetPhysicalDeviceSurfacePresentModesKHRFn =
        loadVulkanFunc(GetPhysicalDeviceSurfacePresentModesKHRFn, instance, "vkGetPhysicalDeviceSurfacePresentModesKHR");

    const vkCreateSwapchainKHR: CreateSwapchainKHRFn =
        loadVulkanFunc(CreateSwapchainKHRFn, instance, "vkCreateSwapchainKHR");

    const vkDestroySwapchainKHR: DestroySwapchainKHRFn =
        loadVulkanFunc(DestroySwapchainKHRFn, instance, "vkDestroySwapchainKHR");

    const vkGetSwapchainImagesKHR: GetSwapchainImagesKHRFn =
        loadVulkanFunc(GetSwapchainImagesKHRFn, instance, "vkGetSwapchainImagesKHR");

    const vkCreateImageView: CreateImageViewFn =
        loadVulkanFunc(CreateImageViewFn, instance, "vkCreateImageView");

    const vkDestroyImageView: DestroyImageViewFn =
        loadVulkanFunc(DestroyImageViewFn, instance, "vkDestroyImageView");

    // Query surface capabilities
    var surface_capabilities: vulkan_c.VkSurfaceCapabilitiesKHR = undefined;
    if (vkGetPhysicalDeviceSurfaceCapabilitiesKHR(selected_device, surface, &surface_capabilities) != vulkan_c.VK_SUCCESS) {
        std.debug.print("Failed to get surface capabilities\n", .{});
        return error.SurfaceCapabilitiesFailed;
    }

    // Query surface formats
    var format_count: u32 = 0;
    if (vkGetPhysicalDeviceSurfaceFormatsKHR(selected_device, surface, &format_count, null) != vulkan_c.VK_SUCCESS) {
        std.debug.print("Failed to get surface format count\n", .{});
        return error.SurfaceFormatsFailed;
    }

    const surface_formats = try allocator.alloc(vulkan_c.VkSurfaceFormatKHR, format_count);
    defer allocator.free(surface_formats);

    if (vkGetPhysicalDeviceSurfaceFormatsKHR(selected_device, surface, &format_count, surface_formats.ptr) != vulkan_c.VK_SUCCESS) {
        std.debug.print("Failed to get surface formats\n", .{});
        return error.SurfaceFormatsFailed;
    }

    // Query present modes
    var present_mode_count: u32 = 0;
    if (vkGetPhysicalDeviceSurfacePresentModesKHR(selected_device, surface, &present_mode_count, null) != vulkan_c.VK_SUCCESS) {
        std.debug.print("Failed to get present mode count\n", .{});
        return error.PresentModesFailed;
    }

    const present_modes = try allocator.alloc(vulkan_c.VkPresentModeKHR, present_mode_count);
    defer allocator.free(present_modes);

    if (vkGetPhysicalDeviceSurfacePresentModesKHR(selected_device, surface, &present_mode_count, present_modes.ptr) != vulkan_c.VK_SUCCESS) {
        std.debug.print("Failed to get present modes\n", .{});
        return error.PresentModesFailed;
    }

    // Choose surface format (prefer SRGB8888 with BGRA or RGBA)
    var surface_format: vulkan_c.VkSurfaceFormatKHR = undefined;
    if (format_count == 1 and surface_formats[0].format == vulkan_c.VK_FORMAT_UNDEFINED) {
        // Any format is allowed
        surface_format = vulkan_c.VkSurfaceFormatKHR{
            .format = vulkan_c.VK_FORMAT_B8G8R8A8_SRGB,
            .colorSpace = vulkan_c.VK_COLOR_SPACE_SRGB_NONLINEAR_KHR,
        };
    } else {
        // Look for SRGB8888
        var found = false;
        for (surface_formats[0..format_count]) |fmt| {
            if (fmt.format == vulkan_c.VK_FORMAT_B8G8R8A8_SRGB and fmt.colorSpace == vulkan_c.VK_COLOR_SPACE_SRGB_NONLINEAR_KHR) {
                surface_format = fmt;
                found = true;
                break;
            }
        }
        if (!found) {
            surface_format = surface_formats[0];
        }
    }

    // Choose present mode (prefer MAILBOX for triple buffering, fallback to FIFO)
    var present_mode: vulkan_c.VkPresentModeKHR = vulkan_c.VK_PRESENT_MODE_FIFO_KHR; // Always supported
    for (present_modes[0..present_mode_count]) |mode| {
        if (mode == vulkan_c.VK_PRESENT_MODE_MAILBOX_KHR) {
            present_mode = mode;
            break;
        }
    }

    // Choose swap extent (swapchain dimensions)
    var extent: vulkan_c.VkExtent2D = undefined;
    if (surface_capabilities.currentExtent.width != 0xFFFFFFFF) {
        extent = surface_capabilities.currentExtent;
    } else {
        extent = vulkan_c.VkExtent2D{
            .width = @min(surface_capabilities.maxImageExtent.width, @max(surface_capabilities.minImageExtent.width, 800)),
            .height = @min(surface_capabilities.maxImageExtent.height, @max(surface_capabilities.minImageExtent.height, 600)),
        };
    }

    // Determine image count (prefer one more than minimum for triple buffering)
    var image_count: u32 = surface_capabilities.minImageCount + 1;
    if (surface_capabilities.maxImageCount > 0 and image_count > surface_capabilities.maxImageCount) {
        image_count = surface_capabilities.maxImageCount;
    }

    // Create swapchain
    const swapchain_info = vulkan_c.VkSwapchainCreateInfoKHR{
        .sType = vulkan_c.VK_STRUCTURE_TYPE_SWAPCHAIN_CREATE_INFO_KHR,
        .surface = surface,
        .minImageCount = image_count,
        .imageFormat = surface_format.format,
        .imageColorSpace = surface_format.colorSpace,
        .imageExtent = extent,
        .imageArrayLayers = 1,
        .imageUsage = vulkan_c.VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT,
        .preTransform = surface_capabilities.currentTransform,
        .compositeAlpha = vulkan_c.VK_COMPOSITE_ALPHA_OPAQUE_BIT_KHR,
        .presentMode = present_mode,
        .clipped = vulkan_c.VK_TRUE,
        .oldSwapchain = null,
    };

    // Handle sharing mode for queue families
    var swapchain_info_ptr = swapchain_info;
    var queue_family_indices: [2]u32 = undefined;

    if (same_family) {
        swapchain_info_ptr.imageSharingMode = vulkan_c.VK_SHARING_MODE_EXCLUSIVE;
    } else {
        swapchain_info_ptr.imageSharingMode = vulkan_c.VK_SHARING_MODE_CONCURRENT;
        swapchain_info_ptr.queueFamilyIndexCount = 2;
        queue_family_indices[0] = graphics_family;
        queue_family_indices[1] = present_family;
        swapchain_info_ptr.pQueueFamilyIndices = &queue_family_indices;
    }

    var swapchain: vulkan_c.VkSwapchainKHR = undefined;
    if (vkCreateSwapchainKHR(device, &swapchain_info_ptr, null, &swapchain) != vulkan_c.VK_SUCCESS) {
        std.debug.print("Failed to create swapchain\n", .{});
        return error.SwapchainCreationFailed;
    }
    defer vkDestroySwapchainKHR(device, swapchain, null);

    std.debug.print("Swapchain created: {}x{} format={}, present_mode={}, images={}\n", .{
        extent.width, extent.height, surface_format.format, present_mode, image_count,
    });

    // Get swapchain images
    var swapchain_image_count: u32 = 0;
    if (vkGetSwapchainImagesKHR(device, swapchain, &swapchain_image_count, null) != vulkan_c.VK_SUCCESS) {
        std.debug.print("Failed to get swapchain image count\n", .{});
        return error.SwapchainImagesFailed;
    }

    const swapchain_images = try allocator.alloc(vulkan_c.VkImage, swapchain_image_count);
    defer allocator.free(swapchain_images);

    if (vkGetSwapchainImagesKHR(device, swapchain, &swapchain_image_count, swapchain_images.ptr) != vulkan_c.VK_SUCCESS) {
        std.debug.print("Failed to get swapchain images\n", .{});
        return error.SwapchainImagesFailed;
    }

    // Create image views for each swapchain image
    const swapchain_image_views = try allocator.alloc(vulkan_c.VkImageView, swapchain_image_count);
    defer {
        for (swapchain_image_views[0..swapchain_image_count]) |view| {
            vkDestroyImageView(device, view, null);
        }
        allocator.free(swapchain_image_views);
    }

    for (swapchain_images[0..swapchain_image_count], 0..) |img, i| {
        const view_info = vulkan_c.VkImageViewCreateInfo{
            .sType = vulkan_c.VK_STRUCTURE_TYPE_IMAGE_VIEW_CREATE_INFO,
            .image = img,
            .viewType = vulkan_c.VK_IMAGE_VIEW_TYPE_2D,
            .format = surface_format.format,
            .subresourceRange = vulkan_c.VkImageSubresourceRange{
                .aspectMask = vulkan_c.VK_IMAGE_ASPECT_COLOR_BIT,
                .baseMipLevel = 0,
                .levelCount = 1,
                .baseArrayLayer = 0,
                .layerCount = 1,
            },
        };

        if (vkCreateImageView(device, &view_info, null, &swapchain_image_views[i]) != vulkan_c.VK_SUCCESS) {
            std.debug.print("Failed to create image view {}\n", .{i});
            return error.ImageViewCreationFailed;
        }
    }

    std.debug.print("Created {} image views\n", .{swapchain_image_count});

    // Shader modules creation
    const DestroyShaderModuleFn = *const fn (
        vulkan_c.VkDevice,
        vulkan_c.VkShaderModule,
        ?*const vulkan_c.VkAllocationCallbacks,
    ) callconv(std.builtin.CallingConvention.c) void;

    const CreateShaderModuleFn = *const fn (
        vulkan_c.VkDevice,
        [*c]const vulkan_c.VkShaderModuleCreateInfo,
        ?*const vulkan_c.VkAllocationCallbacks,
        *vulkan_c.VkShaderModule,
    ) callconv(std.builtin.CallingConvention.c) vulkan_c.VkResult;

    const vkCreateShaderModule: CreateShaderModuleFn =
        loadVulkanFunc(CreateShaderModuleFn, instance, "vkCreateShaderModule");

    const vkDestroyShaderModule: DestroyShaderModuleFn =
        loadVulkanFunc(DestroyShaderModuleFn, instance, "vkDestroyShaderModule");

    // Embed SPIR-V bytecode
    const vert_spirv = @embedFile("shaders/triangle.vert.spv");
    const frag_spirv = @embedFile("shaders/triangle.frag.spv");

    // Create vertex shader module
    const vert_info = vulkan_c.VkShaderModuleCreateInfo{
        .sType = vulkan_c.VK_STRUCTURE_TYPE_SHADER_MODULE_CREATE_INFO,
        .codeSize = vert_spirv.len,
        .pCode = @ptrCast(@alignCast(vert_spirv)),
    };

    var vert_shader_module: vulkan_c.VkShaderModule = undefined;
    if (vkCreateShaderModule(device, &vert_info, null, &vert_shader_module) != vulkan_c.VK_SUCCESS) {
        std.debug.print("Failed to create vertex shader module\n", .{});
        return error.VertexShaderModuleFailed;
    }
    defer vkDestroyShaderModule(device, vert_shader_module, null);

    // Create fragment shader module
    const frag_info = vulkan_c.VkShaderModuleCreateInfo{
        .sType = vulkan_c.VK_STRUCTURE_TYPE_SHADER_MODULE_CREATE_INFO,
        .codeSize = frag_spirv.len,
        .pCode = @ptrCast(@alignCast(frag_spirv)),
    };

    var frag_shader_module: vulkan_c.VkShaderModule = undefined;
    if (vkCreateShaderModule(device, &frag_info, null, &frag_shader_module) != vulkan_c.VK_SUCCESS) {
        std.debug.print("Failed to create fragment shader module\n", .{});
        return error.FragmentShaderModuleFailed;
    }
    defer vkDestroyShaderModule(device, frag_shader_module, null);

    std.debug.print("Shader modules created successfully\n", .{});

    // Render pass creation
    const CreateRenderPassFn = *const fn (
        vulkan_c.VkDevice,
        [*c]const vulkan_c.VkRenderPassCreateInfo,
        ?*const vulkan_c.VkAllocationCallbacks,
        *vulkan_c.VkRenderPass,
    ) callconv(std.builtin.CallingConvention.c) vulkan_c.VkResult;

    const DestroyRenderPassFn = *const fn (
        vulkan_c.VkDevice,
        vulkan_c.VkRenderPass,
        ?*const vulkan_c.VkAllocationCallbacks,
    ) callconv(std.builtin.CallingConvention.c) void;

    const vkCreateRenderPass: CreateRenderPassFn =
        loadVulkanFunc(CreateRenderPassFn, instance, "vkCreateRenderPass");

    const vkDestroyRenderPass: DestroyRenderPassFn =
        loadVulkanFunc(DestroyRenderPassFn, instance, "vkDestroyRenderPass");

    // Color attachment
    const color_attachment = vulkan_c.VkAttachmentDescription{
        .format = surface_format.format,
        .samples = vulkan_c.VK_SAMPLE_COUNT_1_BIT,
        .loadOp = vulkan_c.VK_ATTACHMENT_LOAD_OP_CLEAR,
        .storeOp = vulkan_c.VK_ATTACHMENT_STORE_OP_STORE,
        .stencilLoadOp = vulkan_c.VK_ATTACHMENT_LOAD_OP_DONT_CARE,
        .stencilStoreOp = vulkan_c.VK_ATTACHMENT_STORE_OP_DONT_CARE,
        .initialLayout = vulkan_c.VK_IMAGE_LAYOUT_UNDEFINED,
        .finalLayout = vulkan_c.VK_IMAGE_LAYOUT_PRESENT_SRC_KHR,
    };

    const color_attachment_ref = vulkan_c.VkAttachmentReference{
        .attachment = 0,
        .layout = vulkan_c.VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL,
    };

    const subpass = vulkan_c.VkSubpassDescription{
        .pipelineBindPoint = vulkan_c.VK_PIPELINE_BIND_POINT_GRAPHICS,
        .colorAttachmentCount = 1,
        .pColorAttachments = &color_attachment_ref,
    };

    const dependency = vulkan_c.VkSubpassDependency{
        .srcSubpass = vulkan_c.VK_SUBPASS_EXTERNAL,
        .dstSubpass = 0,
        .srcStageMask = vulkan_c.VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT,
        .srcAccessMask = 0,
        .dstStageMask = vulkan_c.VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT,
        .dstAccessMask = vulkan_c.VK_ACCESS_COLOR_ATTACHMENT_WRITE_BIT,
    };

    const render_pass_info = vulkan_c.VkRenderPassCreateInfo{
        .sType = vulkan_c.VK_STRUCTURE_TYPE_RENDER_PASS_CREATE_INFO,
        .attachmentCount = 1,
        .pAttachments = &color_attachment,
        .subpassCount = 1,
        .pSubpasses = &subpass,
        .dependencyCount = 1,
        .pDependencies = &dependency,
    };

    var render_pass: vulkan_c.VkRenderPass = undefined;
    if (vkCreateRenderPass(device, &render_pass_info, null, &render_pass) != vulkan_c.VK_SUCCESS) {
        std.debug.print("Failed to create render pass\n", .{});
        return error.RenderPassCreationFailed;
    }
    defer vkDestroyRenderPass(device, render_pass, null);

    std.debug.print("Render pass created successfully\n", .{});

    // Create descriptor pool for ImGui
    const pool_sizes = [_]vulkan_c.VkDescriptorPoolSize{
        .{ .type = vulkan_c.VK_DESCRIPTOR_TYPE_SAMPLER, .descriptorCount = 1 },
        .{ .type = vulkan_c.VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER, .descriptorCount = 1 },
    };

    const descriptor_pool_info = vulkan_c.VkDescriptorPoolCreateInfo{
        .sType = vulkan_c.VK_STRUCTURE_TYPE_DESCRIPTOR_POOL_CREATE_INFO,
        .poolSizeCount = pool_sizes.len,
        .pPoolSizes = &pool_sizes[0],
        .maxSets = 2,
    };

    var descriptor_pool: vulkan_c.VkDescriptorPool = undefined;
    const CreateDescriptorPoolFn = *const fn (
        vulkan_c.VkDevice,
        [*c]const vulkan_c.VkDescriptorPoolCreateInfo,
        ?*const vulkan_c.VkAllocationCallbacks,
        *vulkan_c.VkDescriptorPool,
    ) callconv(std.builtin.CallingConvention.c) vulkan_c.VkResult;

    const vkCreateDescriptorPool: CreateDescriptorPoolFn =
        loadVulkanFunc(CreateDescriptorPoolFn, instance, "vkCreateDescriptorPool");

    if (vkCreateDescriptorPool(device, &descriptor_pool_info, null, &descriptor_pool) != vulkan_c.VK_SUCCESS) {
        std.debug.print("Failed to create descriptor pool for ImGui\n", .{});
        return error.DescriptorPoolCreationFailed;
    }
    defer {
        const DestroyDescriptorPoolFn = *const fn (
            vulkan_c.VkDevice,
            vulkan_c.VkDescriptorPool,
            ?*const vulkan_c.VkAllocationCallbacks,
        ) callconv(std.builtin.CallingConvention.c) void;

        const vkDestroyDescriptorPool: DestroyDescriptorPoolFn =
            loadVulkanFunc(DestroyDescriptorPoolFn, instance, "vkDestroyDescriptorPool");
        vkDestroyDescriptorPool(device, descriptor_pool, null);
    }

    std.debug.print("Descriptor pool created for ImGui\n", .{});

    // Initialize ImGui GLFW backend
    imgui_wrapper.imgui_wrapper_glfw_set_window(@as(?*anyopaque, @ptrCast(window)));
    imgui_wrapper.imgui_wrapper_glfw_init();

    // Initialize ImGui Vulkan backend
    imgui_wrapper.imgui_wrapper_vulkan_init(@as(?*anyopaque, @ptrCast(instance)), @as(?*anyopaque, @ptrCast(selected_device)), @as(?*anyopaque, @ptrCast(device)), graphics_family, @as(?*anyopaque, @ptrCast(graphics_queue)), @as(?*anyopaque, null), // PipelineCache (null)
        @as(?*anyopaque, @ptrCast(descriptor_pool)), 2, // MinImageCount
        swapchain_image_count, @as(?*anyopaque, @ptrCast(render_pass)), vulkan_c.VK_SAMPLE_COUNT_1_BIT, @as(?*anyopaque, null), // Allocator
        null // CheckVkResultFn
    );

    std.debug.print("ImGui backends initialized\n", .{});

    // Framebuffer creation
    const CreateFramebufferFn = *const fn (
        vulkan_c.VkDevice,
        [*c]const vulkan_c.VkFramebufferCreateInfo,
        ?*const vulkan_c.VkAllocationCallbacks,
        *vulkan_c.VkFramebuffer,
    ) callconv(std.builtin.CallingConvention.c) vulkan_c.VkResult;

    const DestroyFramebufferFn = *const fn (
        vulkan_c.VkDevice,
        vulkan_c.VkFramebuffer,
        ?*const vulkan_c.VkAllocationCallbacks,
    ) callconv(std.builtin.CallingConvention.c) void;

    const vkCreateFramebuffer: CreateFramebufferFn =
        loadVulkanFunc(CreateFramebufferFn, instance, "vkCreateFramebuffer");

    const vkDestroyFramebuffer: DestroyFramebufferFn =
        loadVulkanFunc(DestroyFramebufferFn, instance, "vkDestroyFramebuffer");

    const framebuffers = try allocator.alloc(vulkan_c.VkFramebuffer, swapchain_image_count);
    defer {
        for (framebuffers[0..swapchain_image_count]) |fb| {
            vkDestroyFramebuffer(device, fb, null);
        }
        allocator.free(framebuffers);
    }

    for (swapchain_image_views[0..swapchain_image_count], 0..) |view, i| {
        const framebuffer_info = vulkan_c.VkFramebufferCreateInfo{
            .sType = vulkan_c.VK_STRUCTURE_TYPE_FRAMEBUFFER_CREATE_INFO,
            .renderPass = render_pass,
            .attachmentCount = 1,
            .pAttachments = &view,
            .width = extent.width,
            .height = extent.height,
            .layers = 1,
        };

        if (vkCreateFramebuffer(device, &framebuffer_info, null, &framebuffers[i]) != vulkan_c.VK_SUCCESS) {
            std.debug.print("Failed to create framebuffer {}\n", .{i});
            return error.FramebufferCreationFailed;
        }
    }

    std.debug.print("Created {} framebuffers\n", .{swapchain_image_count});

    // Command pool and command buffers
    const CreateCommandPoolFn = *const fn (
        vulkan_c.VkDevice,
        [*c]const vulkan_c.VkCommandPoolCreateInfo,
        ?*const vulkan_c.VkAllocationCallbacks,
        *vulkan_c.VkCommandPool,
    ) callconv(std.builtin.CallingConvention.c) vulkan_c.VkResult;

    const DestroyCommandPoolFn = *const fn (
        vulkan_c.VkDevice,
        vulkan_c.VkCommandPool,
        ?*const vulkan_c.VkAllocationCallbacks,
    ) callconv(std.builtin.CallingConvention.c) void;

    const AllocateCommandBuffersFn = *const fn (
        vulkan_c.VkDevice,
        [*c]const vulkan_c.VkCommandBufferAllocateInfo,
        [*]vulkan_c.VkCommandBuffer,
    ) callconv(std.builtin.CallingConvention.c) vulkan_c.VkResult;

    const FreeCommandBuffersFn = *const fn (
        vulkan_c.VkDevice,
        vulkan_c.VkCommandPool,
        u32,
        [*]const vulkan_c.VkCommandBuffer,
    ) callconv(std.builtin.CallingConvention.c) void;

    const vkCreateCommandPool: CreateCommandPoolFn =
        loadVulkanFunc(CreateCommandPoolFn, instance, "vkCreateCommandPool");

    const vkDestroyCommandPool: DestroyCommandPoolFn =
        loadVulkanFunc(DestroyCommandPoolFn, instance, "vkDestroyCommandPool");

    const vkAllocateCommandBuffers: AllocateCommandBuffersFn =
        loadVulkanFunc(AllocateCommandBuffersFn, instance, "vkAllocateCommandBuffers");

    const vkFreeCommandBuffers: FreeCommandBuffersFn =
        loadVulkanFunc(FreeCommandBuffersFn, instance, "vkFreeCommandBuffers");

    // Create command pool
    const command_pool_info = vulkan_c.VkCommandPoolCreateInfo{
        .sType = vulkan_c.VK_STRUCTURE_TYPE_COMMAND_POOL_CREATE_INFO,
        .queueFamilyIndex = graphics_family,
        .flags = vulkan_c.VK_COMMAND_POOL_CREATE_RESET_COMMAND_BUFFER_BIT,
    };

    var command_pool: vulkan_c.VkCommandPool = undefined;
    if (vkCreateCommandPool(device, &command_pool_info, null, &command_pool) != vulkan_c.VK_SUCCESS) {
        std.debug.print("Failed to create command pool\n", .{});
        return error.CommandPoolCreationFailed;
    }
    defer vkDestroyCommandPool(device, command_pool, null);

    // Allocate command buffers (one per framebuffer)
    const command_buffers = try allocator.alloc(vulkan_c.VkCommandBuffer, swapchain_image_count);
    defer {
        vkFreeCommandBuffers(device, command_pool, swapchain_image_count, command_buffers.ptr);
        allocator.free(command_buffers);
    }

    const cmd_alloc_info = vulkan_c.VkCommandBufferAllocateInfo{
        .sType = vulkan_c.VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO,
        .commandPool = command_pool,
        .level = vulkan_c.VK_COMMAND_BUFFER_LEVEL_PRIMARY,
        .commandBufferCount = swapchain_image_count,
    };

    if (vkAllocateCommandBuffers(device, &cmd_alloc_info, command_buffers.ptr) != vulkan_c.VK_SUCCESS) {
        std.debug.print("Failed to allocate command buffers\n", .{});
        return error.CommandBufferAllocationFailed;
    }

    std.debug.print("Allocated {} command buffers\n", .{swapchain_image_count});

    // Graphics pipeline creation
    const CreatePipelineLayoutFn = *const fn (
        vulkan_c.VkDevice,
        [*c]const vulkan_c.VkPipelineLayoutCreateInfo,
        ?*const vulkan_c.VkAllocationCallbacks,
        *vulkan_c.VkPipelineLayout,
    ) callconv(std.builtin.CallingConvention.c) vulkan_c.VkResult;

    const DestroyPipelineLayoutFn = *const fn (
        vulkan_c.VkDevice,
        vulkan_c.VkPipelineLayout,
        ?*const vulkan_c.VkAllocationCallbacks,
    ) callconv(std.builtin.CallingConvention.c) void;

    const CreateGraphicsPipelinesFn = *const fn (
        vulkan_c.VkDevice,
        vulkan_c.VkPipelineCache,
        u32,
        [*c]const vulkan_c.VkGraphicsPipelineCreateInfo,
        ?*const vulkan_c.VkAllocationCallbacks,
        [*]vulkan_c.VkPipeline,
    ) callconv(std.builtin.CallingConvention.c) vulkan_c.VkResult;

    const DestroyPipelineFn = *const fn (
        vulkan_c.VkDevice,
        vulkan_c.VkPipeline,
        ?*const vulkan_c.VkAllocationCallbacks,
    ) callconv(std.builtin.CallingConvention.c) void;

    const vkCreatePipelineLayout: CreatePipelineLayoutFn =
        loadVulkanFunc(CreatePipelineLayoutFn, instance, "vkCreatePipelineLayout");

    const vkDestroyPipelineLayout: DestroyPipelineLayoutFn =
        loadVulkanFunc(DestroyPipelineLayoutFn, instance, "vkDestroyPipelineLayout");

    const vkCreateGraphicsPipelines: CreateGraphicsPipelinesFn =
        loadVulkanFunc(CreateGraphicsPipelinesFn, instance, "vkCreateGraphicsPipelines");

    const vkDestroyPipeline: DestroyPipelineFn =
        loadVulkanFunc(DestroyPipelineFn, instance, "vkDestroyPipeline");

    // Create pipeline layout (empty for now, no descriptors)
    const pipeline_layout_info = vulkan_c.VkPipelineLayoutCreateInfo{
        .sType = vulkan_c.VK_STRUCTURE_TYPE_PIPELINE_LAYOUT_CREATE_INFO,
    };

    var pipeline_layout: vulkan_c.VkPipelineLayout = undefined;
    if (vkCreatePipelineLayout(device, &pipeline_layout_info, null, &pipeline_layout) != vulkan_c.VK_SUCCESS) {
        std.debug.print("Failed to create pipeline layout\n", .{});
        return error.PipelineLayoutCreationFailed;
    }
    defer vkDestroyPipelineLayout(device, pipeline_layout, null);

    // Shader stages
    const vert_stage_info = vulkan_c.VkPipelineShaderStageCreateInfo{
        .sType = vulkan_c.VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO,
        .stage = vulkan_c.VK_SHADER_STAGE_VERTEX_BIT,
        .module = vert_shader_module,
        .pName = "main",
    };

    const frag_stage_info = vulkan_c.VkPipelineShaderStageCreateInfo{
        .sType = vulkan_c.VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO,
        .stage = vulkan_c.VK_SHADER_STAGE_FRAGMENT_BIT,
        .module = frag_shader_module,
        .pName = "main",
    };

    const shader_stages = [_]vulkan_c.VkPipelineShaderStageCreateInfo{ vert_stage_info, frag_stage_info };

    // Vertex input state (no vertex buffers for now, hardcoded in shader)
    const vertex_input_info = vulkan_c.VkPipelineVertexInputStateCreateInfo{
        .sType = vulkan_c.VK_STRUCTURE_TYPE_PIPELINE_VERTEX_INPUT_STATE_CREATE_INFO,
    };

    // Input assembly
    const input_assembly = vulkan_c.VkPipelineInputAssemblyStateCreateInfo{
        .sType = vulkan_c.VK_STRUCTURE_TYPE_PIPELINE_INPUT_ASSEMBLY_STATE_CREATE_INFO,
        .topology = vulkan_c.VK_PRIMITIVE_TOPOLOGY_TRIANGLE_LIST,
        .primitiveRestartEnable = vulkan_c.VK_FALSE,
    };

    // Viewport and scissor
    const viewport = vulkan_c.VkViewport{
        .x = 0.0,
        .y = 0.0,
        .width = @floatFromInt(extent.width),
        .height = @floatFromInt(extent.height),
        .minDepth = 0.0,
        .maxDepth = 1.0,
    };

    const scissor = vulkan_c.VkRect2D{
        .offset = .{ .x = 0, .y = 0 },
        .extent = extent,
    };

    const viewport_state = vulkan_c.VkPipelineViewportStateCreateInfo{
        .sType = vulkan_c.VK_STRUCTURE_TYPE_PIPELINE_VIEWPORT_STATE_CREATE_INFO,
        .viewportCount = 1,
        .pViewports = &viewport,
        .scissorCount = 1,
        .pScissors = &scissor,
    };

    // Rasterizer
    const rasterizer = vulkan_c.VkPipelineRasterizationStateCreateInfo{
        .sType = vulkan_c.VK_STRUCTURE_TYPE_PIPELINE_RASTERIZATION_STATE_CREATE_INFO,
        .depthClampEnable = vulkan_c.VK_FALSE,
        .rasterizerDiscardEnable = vulkan_c.VK_FALSE,
        .polygonMode = vulkan_c.VK_POLYGON_MODE_FILL,
        .cullMode = vulkan_c.VK_CULL_MODE_NONE,
        .frontFace = vulkan_c.VK_FRONT_FACE_CLOCKWISE,
        .depthBiasEnable = vulkan_c.VK_FALSE,
        .lineWidth = 1.0,
    };

    // Multisampling (no MSAA)
    const multisampling = vulkan_c.VkPipelineMultisampleStateCreateInfo{
        .sType = vulkan_c.VK_STRUCTURE_TYPE_PIPELINE_MULTISAMPLE_STATE_CREATE_INFO,
        .rasterizationSamples = vulkan_c.VK_SAMPLE_COUNT_1_BIT,
        .sampleShadingEnable = vulkan_c.VK_FALSE,
    };

    // Color blending (no blending, write all channels)
    const color_blend_attachment = vulkan_c.VkPipelineColorBlendAttachmentState{
        .colorWriteMask = vulkan_c.VK_COLOR_COMPONENT_R_BIT | vulkan_c.VK_COLOR_COMPONENT_G_BIT | vulkan_c.VK_COLOR_COMPONENT_B_BIT | vulkan_c.VK_COLOR_COMPONENT_A_BIT,
        .blendEnable = vulkan_c.VK_FALSE,
    };

    const color_blending = vulkan_c.VkPipelineColorBlendStateCreateInfo{
        .sType = vulkan_c.VK_STRUCTURE_TYPE_PIPELINE_COLOR_BLEND_STATE_CREATE_INFO,
        .logicOpEnable = vulkan_c.VK_FALSE,
        .attachmentCount = 1,
        .pAttachments = &color_blend_attachment,
    };

    // Dynamic state (none for now)
    const pipeline_info = vulkan_c.VkGraphicsPipelineCreateInfo{
        .sType = vulkan_c.VK_STRUCTURE_TYPE_GRAPHICS_PIPELINE_CREATE_INFO,
        .stageCount = 2,
        .pStages = &shader_stages[0],
        .pVertexInputState = &vertex_input_info,
        .pInputAssemblyState = &input_assembly,
        .pViewportState = &viewport_state,
        .pRasterizationState = &rasterizer,
        .pMultisampleState = &multisampling,
        .pColorBlendState = &color_blending,
        .layout = pipeline_layout,
        .renderPass = render_pass,
        .subpass = 0,
    };

    var pipeline: vulkan_c.VkPipeline = undefined;
    if (vkCreateGraphicsPipelines(device, null, 1, &pipeline_info, null, @ptrCast(&pipeline)) != vulkan_c.VK_SUCCESS) {
        std.debug.print("Failed to create graphics pipeline\n", .{});
        return error.PipelineCreationFailed;
    }
    defer vkDestroyPipeline(device, pipeline, null);

    std.debug.print("Graphics pipeline created successfully\n", .{});

    // Record command buffers
    const BeginCommandBufferFn = *const fn (
        vulkan_c.VkCommandBuffer,
        [*c]const vulkan_c.VkCommandBufferBeginInfo,
    ) callconv(std.builtin.CallingConvention.c) vulkan_c.VkResult;

    const EndCommandBufferFn = *const fn (
        vulkan_c.VkCommandBuffer,
    ) callconv(std.builtin.CallingConvention.c) vulkan_c.VkResult;

    const CmdBeginRenderPassFn = *const fn (
        vulkan_c.VkCommandBuffer,
        [*c]const vulkan_c.VkRenderPassBeginInfo,
        vulkan_c.VkSubpassContents,
    ) callconv(std.builtin.CallingConvention.c) void;

    const CmdBindPipelineFn = *const fn (
        vulkan_c.VkCommandBuffer,
        vulkan_c.VkPipelineBindPoint,
        vulkan_c.VkPipeline,
    ) callconv(std.builtin.CallingConvention.c) void;

    const CmdDrawFn = *const fn (
        vulkan_c.VkCommandBuffer,
        u32,
        u32,
        u32,
        u32,
    ) callconv(std.builtin.CallingConvention.c) void;

    const CmdEndRenderPassFn = *const fn (
        vulkan_c.VkCommandBuffer,
    ) callconv(std.builtin.CallingConvention.c) void;

    const vkBeginCommandBuffer: BeginCommandBufferFn =
        loadVulkanFunc(BeginCommandBufferFn, instance, "vkBeginCommandBuffer");

    const vkEndCommandBuffer: EndCommandBufferFn =
        loadVulkanFunc(EndCommandBufferFn, instance, "vkEndCommandBuffer");

    const vkCmdBeginRenderPass: CmdBeginRenderPassFn =
        loadVulkanFunc(CmdBeginRenderPassFn, instance, "vkCmdBeginRenderPass");

    const vkCmdBindPipeline: CmdBindPipelineFn =
        loadVulkanFunc(CmdBindPipelineFn, instance, "vkCmdBindPipeline");

    const vkCmdDraw: CmdDrawFn =
        loadVulkanFunc(CmdDrawFn, instance, "vkCmdDraw");

    const vkCmdEndRenderPass: CmdEndRenderPassFn =
        loadVulkanFunc(CmdEndRenderPassFn, instance, "vkCmdEndRenderPass");

    const clear_color = vulkan_c.VkClearValue{ .color = .{ .float32 = .{ 0.0, 0.0, 0.0, 1.0 } } };

    for (command_buffers[0..swapchain_image_count], 0..) |cmd, i| {
        const begin_info = vulkan_c.VkCommandBufferBeginInfo{
            .sType = vulkan_c.VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO,
            .flags = vulkan_c.VK_COMMAND_BUFFER_USAGE_SIMULTANEOUS_USE_BIT,
        };

        if (vkBeginCommandBuffer(cmd, &begin_info) != vulkan_c.VK_SUCCESS) {
            std.debug.print("Failed to begin command buffer {}\n", .{i});
            return error.CommandBufferBeginFailed;
        }

        const rp_begin = vulkan_c.VkRenderPassBeginInfo{
            .sType = vulkan_c.VK_STRUCTURE_TYPE_RENDER_PASS_BEGIN_INFO,
            .renderPass = render_pass,
            .framebuffer = framebuffers[i],
            .renderArea = .{ .offset = .{ .x = 0, .y = 0 }, .extent = extent },
            .clearValueCount = 1,
            .pClearValues = &clear_color,
        };

        vkCmdBeginRenderPass(cmd, &rp_begin, vulkan_c.VK_SUBPASS_CONTENTS_INLINE);
        vkCmdBindPipeline(cmd, vulkan_c.VK_PIPELINE_BIND_POINT_GRAPHICS, pipeline);
        vkCmdDraw(cmd, 3, 1, 0, 0);
        vkCmdEndRenderPass(cmd);

        if (vkEndCommandBuffer(cmd) != vulkan_c.VK_SUCCESS) {
            std.debug.print("Failed to end command buffer {}\n", .{i});
            return error.CommandBufferEndFailed;
        }
    }

    std.debug.print("Command buffers recorded successfully\n", .{});

    // Synchronization primitives
    const CreateSemaphoreFn = *const fn (
        vulkan_c.VkDevice,
        [*c]const vulkan_c.VkSemaphoreCreateInfo,
        ?*const vulkan_c.VkAllocationCallbacks,
        *vulkan_c.VkSemaphore,
    ) callconv(std.builtin.CallingConvention.c) vulkan_c.VkResult;

    const DestroySemaphoreFn = *const fn (
        vulkan_c.VkDevice,
        vulkan_c.VkSemaphore,
        ?*const vulkan_c.VkAllocationCallbacks,
    ) callconv(std.builtin.CallingConvention.c) void;

    const CreateFenceFn = *const fn (
        vulkan_c.VkDevice,
        [*c]const vulkan_c.VkFenceCreateInfo,
        ?*const vulkan_c.VkAllocationCallbacks,
        *vulkan_c.VkFence,
    ) callconv(std.builtin.CallingConvention.c) vulkan_c.VkResult;

    const DestroyFenceFn = *const fn (
        vulkan_c.VkDevice,
        vulkan_c.VkFence,
        ?*const vulkan_c.VkAllocationCallbacks,
    ) callconv(std.builtin.CallingConvention.c) void;

    const WaitForFencesFn = *const fn (
        vulkan_c.VkDevice,
        u32,
        [*]const vulkan_c.VkFence,
        vulkan_c.VkBool32,
        u64,
    ) callconv(std.builtin.CallingConvention.c) vulkan_c.VkResult;

    const ResetFencesFn = *const fn (
        vulkan_c.VkDevice,
        u32,
        [*]const vulkan_c.VkFence,
    ) callconv(std.builtin.CallingConvention.c) vulkan_c.VkResult;

    const vkCreateSemaphore: CreateSemaphoreFn =
        loadVulkanFunc(CreateSemaphoreFn, instance, "vkCreateSemaphore");

    const vkDestroySemaphore: DestroySemaphoreFn =
        loadVulkanFunc(DestroySemaphoreFn, instance, "vkDestroySemaphore");

    const vkCreateFence: CreateFenceFn =
        loadVulkanFunc(CreateFenceFn, instance, "vkCreateFence");

    const vkDestroyFence: DestroyFenceFn =
        loadVulkanFunc(DestroyFenceFn, instance, "vkDestroyFence");

    const vkWaitForFences: WaitForFencesFn =
        loadVulkanFunc(WaitForFencesFn, instance, "vkWaitForFences");

    const vkResetFences: ResetFencesFn =
        loadVulkanFunc(ResetFencesFn, instance, "vkResetFences");

    const AcquireNextImageKHRFn = *const fn (
        vulkan_c.VkDevice,
        vulkan_c.VkSwapchainKHR,
        u64,
        vulkan_c.VkSemaphore,
        vulkan_c.VkFence,
        *u32,
    ) callconv(std.builtin.CallingConvention.c) vulkan_c.VkResult;

    const vkAcquireNextImageKHR: AcquireNextImageKHRFn =
        loadVulkanFunc(AcquireNextImageKHRFn, instance, "vkAcquireNextImageKHR");

    const QueueSubmitFn = *const fn (
        vulkan_c.VkQueue,
        u32,
        [*]const vulkan_c.VkSubmitInfo,
        vulkan_c.VkFence,
    ) callconv(std.builtin.CallingConvention.c) vulkan_c.VkResult;

    const vkQueueSubmit: QueueSubmitFn =
        loadVulkanFunc(QueueSubmitFn, instance, "vkQueueSubmit");

    const QueuePresentKHRFn = *const fn (
        vulkan_c.VkQueue,
        [*]const vulkan_c.VkPresentInfoKHR,
    ) callconv(std.builtin.CallingConvention.c) vulkan_c.VkResult;

    const vkQueuePresentKHR: QueuePresentKHRFn =
        loadVulkanFunc(QueuePresentKHRFn, instance, "vkQueuePresentKHR");

    const QueueWaitIdleFn = *const fn (
        vulkan_c.VkQueue,
    ) callconv(std.builtin.CallingConvention.c) vulkan_c.VkResult;

    const vkQueueWaitIdle: QueueWaitIdleFn =
        loadVulkanFunc(QueueWaitIdleFn, instance, "vkQueueWaitIdle");

    var image_available: vulkan_c.VkSemaphore = undefined;
    var render_finished: vulkan_c.VkSemaphore = undefined;
    var in_flight_fence: vulkan_c.VkFence = undefined;

    const semaphore_info = vulkan_c.VkSemaphoreCreateInfo{
        .sType = vulkan_c.VK_STRUCTURE_TYPE_SEMAPHORE_CREATE_INFO,
    };

    if (vkCreateSemaphore(device, &semaphore_info, null, &image_available) != vulkan_c.VK_SUCCESS or
        vkCreateSemaphore(device, &semaphore_info, null, &render_finished) != vulkan_c.VK_SUCCESS)
    {
        std.debug.print("Failed to create semaphores\n", .{});
        return error.SemaphoreCreationFailed;
    }
    defer vkDestroySemaphore(device, image_available, null);
    defer vkDestroySemaphore(device, render_finished, null);

    const fence_info = vulkan_c.VkFenceCreateInfo{
        .sType = vulkan_c.VK_STRUCTURE_TYPE_FENCE_CREATE_INFO,
        .flags = vulkan_c.VK_FENCE_CREATE_SIGNALED_BIT, // Start signaled so first frame can proceed
    };

    if (vkCreateFence(device, &fence_info, null, &in_flight_fence) != vulkan_c.VK_SUCCESS) {
        std.debug.print("Failed to create fence\n", .{});
        return error.FenceCreationFailed;
    }
    defer vkDestroyFence(device, in_flight_fence, null);

    std.debug.print("Synchronization primitives created\n", .{});

    std.debug.print("Starting render loop...\n", .{});

    // Main loop
    while (glfw.glfwWindowShouldClose(window) == 0) {
        glfw.glfwPollEvents();

        // Wait for previous frame to finish
        _ = vkWaitForFences(device, 1, @ptrCast(&in_flight_fence), vulkan_c.VK_TRUE, ~@as(u64, 0));
        _ = vkResetFences(device, 1, @ptrCast(&in_flight_fence));

        // Acquire next swapchain image
        var image_index: u32 = undefined;
        if (vkAcquireNextImageKHR(device, swapchain, ~@as(u64, 0), image_available, null, &image_index) != vulkan_c.VK_SUCCESS) {
            continue;
        }

        // ImGui new frame
        imgui_wrapper.imgui_wrapper_new_frame();

        // Begin command buffer recording
        const begin_info = vulkan_c.VkCommandBufferBeginInfo{
            .sType = vulkan_c.VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO,
            .flags = vulkan_c.VK_COMMAND_BUFFER_USAGE_SIMULTANEOUS_USE_BIT,
        };

        if (vulkan_c.vkBeginCommandBuffer(command_buffers[image_index], &begin_info) != vulkan_c.VK_SUCCESS) {
            continue;
        }

        const render_clear_color = vulkan_c.VkClearValue{ .color = .{ .float32 = .{ 0.0, 0.0, 0.0, 1.0 } } };

        const rp_begin = vulkan_c.VkRenderPassBeginInfo{
            .sType = vulkan_c.VK_STRUCTURE_TYPE_RENDER_PASS_BEGIN_INFO,
            .renderPass = render_pass,
            .framebuffer = framebuffers[image_index],
            .renderArea = .{ .offset = .{ .x = 0, .y = 0 }, .extent = extent },
            .clearValueCount = 1,
            .pClearValues = &render_clear_color,
        };

        vulkan_c.vkCmdBeginRenderPass(command_buffers[image_index], &rp_begin, vulkan_c.VK_SUBPASS_CONTENTS_INLINE);
        vulkan_c.vkCmdBindPipeline(command_buffers[image_index], vulkan_c.VK_PIPELINE_BIND_POINT_GRAPHICS, pipeline);

        // Render ImGui
        imgui_wrapper.imgui_wrapper_render(@as(?*anyopaque, @ptrCast(command_buffers[image_index])));

        vulkan_c.vkCmdDraw(command_buffers[image_index], 3, 1, 0, 0);
        vulkan_c.vkCmdEndRenderPass(command_buffers[image_index]);

        if (vulkan_c.vkEndCommandBuffer(command_buffers[image_index]) != vulkan_c.VK_SUCCESS) {
            continue;
        }

        // Submit command buffer
        const submit_info = vulkan_c.VkSubmitInfo{
            .sType = vulkan_c.VK_STRUCTURE_TYPE_SUBMIT_INFO,
            .waitSemaphoreCount = 1,
            .pWaitSemaphores = &image_available,
            .pWaitDstStageMask = &[_]vulkan_c.VkPipelineStageFlags{vulkan_c.VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT},
            .commandBufferCount = 1,
            .pCommandBuffers = &command_buffers[image_index],
            .signalSemaphoreCount = 1,
            .pSignalSemaphores = &render_finished,
        };

        if (vkQueueSubmit(graphics_queue, 1, @ptrCast(&submit_info), in_flight_fence) != vulkan_c.VK_SUCCESS) {
            std.debug.print("Failed to submit draw command buffer\n", .{});
            break;
        }

        // Present
        const present_info = vulkan_c.VkPresentInfoKHR{
            .sType = vulkan_c.VK_STRUCTURE_TYPE_PRESENT_INFO_KHR,
            .waitSemaphoreCount = 1,
            .pWaitSemaphores = &render_finished,
            .swapchainCount = 1,
            .pSwapchains = &swapchain,
            .pImageIndices = &image_index,
        };

        _ = vkQueuePresentKHR(present_queue, @ptrCast(&present_info));
    }

    // Cleanup
    _ = vkQueueWaitIdle(present_queue);

    // Shutdown ImGui
    imgui_wrapper.imgui_wrapper_vulkan_shutdown();
    imgui_wrapper.imgui_wrapper_glfw_shutdown();
}
