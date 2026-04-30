const std = @import("std");
const c = @import("c");

// Vulkan function loader using GLFW's vkGetInstanceProcAddress
fn loadVulkanFunc(comptime T: type, instance: c.VkInstance, name: [*c]const u8) T {
    const func = c.glfwGetInstanceProcAddress(instance, name);
    return @ptrCast(@alignCast(func));
}

pub fn main() !void {
    var gpa = std.heap.DebugAllocator(.{}){};
    const allocator = gpa.allocator();
    defer _ = gpa.deinit();

    // Initialize GLFW
    if (c.glfwInit() == 0) {
        std.debug.print("Failed to initialize GLFW\n", .{});
        return error.GlfwInitFailed;
    }
    defer c.glfwTerminate();

    // Check Vulkan support
    if (c.glfwVulkanSupported() == 0) {
        std.debug.print("Vulkan not supported by GLFW\n", .{});
        return error.VulkanNotSupported;
    }

    // Window hints for Vulkan (no OpenGL context)
    c.glfwWindowHint(c.GLFW_CLIENT_API, c.GLFW_NO_API);

    // Create window
    const window = c.glfwCreateWindow(800, 600, "VK Zig Engine", null, null) orelse {
        std.debug.print("Failed to create window\n", .{});
        return error.WindowCreationFailed;
    };
    defer c.glfwDestroyWindow(window);

    // Get required Vulkan instance extensions from GLFW
    var ext_count: u32 = 0;
    const extensions = c.glfwGetRequiredInstanceExtensions(&ext_count);
    std.debug.print("Required extensions count: {}\n", .{ext_count});
    for (extensions[0..ext_count]) |ext| {
        std.debug.print("  Extension: {s}\n", .{std.mem.span(ext)});
    }

    // Create Vulkan instance
    const app_info = c.VkApplicationInfo{
        .sType = c.VK_STRUCTURE_TYPE_APPLICATION_INFO,
        .pApplicationName = "VK Zig Engine",
        .applicationVersion = (@as(u32, 1) << 22) | (@as(u32, 0) << 12),
        .apiVersion = (@as(u32, 1) << 22) | (@as(u32, 0) << 12), // Vulkan 1.0
    };

    const instance_create_info = c.VkInstanceCreateInfo{
        .sType = c.VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO,
        .pApplicationInfo = &app_info,
        .enabledExtensionCount = @intCast(ext_count),
        .ppEnabledExtensionNames = extensions,
    };

    // Load vkCreateInstance function
    const CreateInstanceFn = *const fn (
        [*c]const c.VkInstanceCreateInfo,
        ?*const c.VkAllocationCallbacks,
        *c.VkInstance,
    ) callconv(std.builtin.CallingConvention.c) c.VkResult;

    const vkCreateInstance: CreateInstanceFn = loadVulkanFunc(CreateInstanceFn, null, "vkCreateInstance");

    var instance: c.VkInstance = undefined;
    if (vkCreateInstance(&instance_create_info, null, &instance) != c.VK_SUCCESS) {
        std.debug.print("Failed to create Vulkan instance\n", .{});
        return error.InstanceFailed;
    }
    defer {
        const DestroyInstanceFn = *const fn (c.VkInstance, ?*const c.VkAllocationCallbacks) callconv(std.builtin.CallingConvention.c) void;
        const vkDestroyInstance: DestroyInstanceFn =
            loadVulkanFunc(DestroyInstanceFn, instance, "vkDestroyInstance");
        vkDestroyInstance(instance, null);
    }

    // Create Vulkan surface using GLFW
    var surface: c.VkSurfaceKHR = undefined;
    const surface_result = c.glfwCreateWindowSurface(
        instance,
        window,
        null,
        &surface,
    );
    if (surface_result != c.VK_SUCCESS) {
        std.debug.print("Failed to create Vulkan surface: {}\n", .{surface_result});
        return error.SurfaceFailed;
    }
    defer {
        const DestroySurfaceFn = *const fn (c.VkInstance, c.VkSurfaceKHR, ?*const c.VkAllocationCallbacks) callconv(std.builtin.CallingConvention.c) void;
        const vkDestroySurfaceKHR: DestroySurfaceFn =
            loadVulkanFunc(DestroySurfaceFn, instance, "vkDestroySurfaceKHR");
        vkDestroySurfaceKHR(instance, surface, null);
    }

    std.debug.print("Vulkan instance and surface created successfully!\n", .{});

    // Physical device selection
    const EnumeratePhysicalDevicesFn = *const fn (
        c.VkInstance,
        *u32,
        ?[*]c.VkPhysicalDevice,
    ) callconv(std.builtin.CallingConvention.c) c.VkResult;

    const GetPhysicalDeviceQueueFamilyPropertiesFn = *const fn (
        c.VkPhysicalDevice,
        *u32,
        ?[*]c.VkQueueFamilyProperties,
    ) callconv(std.builtin.CallingConvention.c) void;

    const GetPhysicalDeviceSurfaceSupportKHRFn = *const fn (
        c.VkPhysicalDevice,
        u32,
        c.VkSurfaceKHR,
        *c.VkBool32,
    ) callconv(std.builtin.CallingConvention.c) c.VkResult;

    const vkEnumeratePhysicalDevices: EnumeratePhysicalDevicesFn =
        loadVulkanFunc(EnumeratePhysicalDevicesFn, instance, "vkEnumeratePhysicalDevices");

    const vkGetPhysicalDeviceQueueFamilyProperties: GetPhysicalDeviceQueueFamilyPropertiesFn =
        loadVulkanFunc(GetPhysicalDeviceQueueFamilyPropertiesFn, instance, "vkGetPhysicalDeviceQueueFamilyProperties");

    const vkGetPhysicalDeviceSurfaceSupportKHR: GetPhysicalDeviceSurfaceSupportKHRFn =
        loadVulkanFunc(GetPhysicalDeviceSurfaceSupportKHRFn, instance, "vkGetPhysicalDeviceSurfaceSupportKHR");

    // Get physical device count
    var device_count: u32 = 0;
    if (vkEnumeratePhysicalDevices(instance, &device_count, null) != c.VK_SUCCESS) {
        std.debug.print("Failed to enumerate physical devices\n", .{});
        return error.EnumerateDevicesFailed;
    }

    if (device_count == 0) {
        std.debug.print("No Vulkan-compatible physical devices found\n", .{});
        return error.NoSuitableDevice;
    }

    // Allocate and get physical devices
    const physical_devices = try allocator.alloc(c.VkPhysicalDevice, device_count);
    defer allocator.free(physical_devices);

    if (vkEnumeratePhysicalDevices(instance, &device_count, physical_devices.ptr) != c.VK_SUCCESS) {
        std.debug.print("Failed to get physical devices\n", .{});
        return error.GetDevicesFailed;
    }

    // Find suitable physical device
    var selected_device: c.VkPhysicalDevice = undefined;
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
        const queue_families = try allocator.alloc(c.VkQueueFamilyProperties, queue_family_count);
        defer allocator.free(queue_families);
        vkGetPhysicalDeviceQueueFamilyProperties(device, &queue_family_count, queue_families.ptr);

        // Check each queue family for this device only
        for (queue_families, 0..) |props, i| {
            const family_idx: u32 = @intCast(i);

            // Check for graphics support
            if (props.queueFlags & c.VK_QUEUE_GRAPHICS_BIT != 0) {
                if (g_family == std.math.maxInt(u32)) {
                    g_family = family_idx;
                }
            }

            // Check for present support
            var present_support: c.VkBool32 = 0;
            if (vkGetPhysicalDeviceSurfaceSupportKHR(device, family_idx, surface, &present_support) == c.VK_SUCCESS) {
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
        c.VkPhysicalDevice,
        [*c]const c.VkDeviceCreateInfo,
        ?*const c.VkAllocationCallbacks,
        *c.VkDevice,
    ) callconv(std.builtin.CallingConvention.c) c.VkResult;

    const GetDeviceQueueFn = *const fn (
        c.VkDevice,
        u32,
        u32,
        *c.VkQueue,
    ) callconv(std.builtin.CallingConvention.c) void;

    const EnumerateDeviceExtensionPropertiesFn = *const fn (
        c.VkPhysicalDevice,
        ?[*:0]const u8,
        *u32,
        ?[*]c.VkExtensionProperties,
    ) callconv(std.builtin.CallingConvention.c) c.VkResult;

    const DestroyDeviceFn = *const fn (
        c.VkDevice,
        ?*const c.VkAllocationCallbacks,
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
    if (vkEnumerateDeviceExtensionProperties(selected_device, null, &extension_count, null) != c.VK_SUCCESS) {
        std.debug.print("Failed to enumerate device extensions\n", .{});
        return error.EnumerateExtensionsFailed;
    }

    const device_extensions = try allocator.alloc(c.VkExtensionProperties, extension_count);
    defer allocator.free(device_extensions);

    if (vkEnumerateDeviceExtensionProperties(selected_device, null, &extension_count, device_extensions.ptr) != c.VK_SUCCESS) {
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
    const queue_create_infos = try allocator.alloc(c.VkDeviceQueueCreateInfo, queue_count);
    defer allocator.free(queue_create_infos);

    queue_create_infos[0] = c.VkDeviceQueueCreateInfo{
        .sType = c.VK_STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO,
        .queueFamilyIndex = graphics_family,
        .queueCount = 1,
        .pQueuePriorities = &queue_priority,
    };

    if (!same_family) {
        queue_create_infos[1] = c.VkDeviceQueueCreateInfo{
            .sType = c.VK_STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO,
            .queueFamilyIndex = present_family,
            .queueCount = 1,
            .pQueuePriorities = &queue_priority,
        };
    }

    // Device extensions to enable
    const enabled_extensions = [_][*c]const u8{swapchain_extension ++ "\x00"};

    const device_create_info = c.VkDeviceCreateInfo{
        .sType = c.VK_STRUCTURE_TYPE_DEVICE_CREATE_INFO,
        .queueCreateInfoCount = @intCast(queue_count),
        .pQueueCreateInfos = &queue_create_infos[0],
        .enabledExtensionCount = 1,
        .ppEnabledExtensionNames = &enabled_extensions[0],
    };

    var device: c.VkDevice = undefined;
    if (vkCreateDevice(selected_device, &device_create_info, null, &device) != c.VK_SUCCESS) {
        std.debug.print("Failed to create logical device\n", .{});
        return error.DeviceCreationFailed;
    }
    defer vkDestroyDevice(device, null);

    // Get queue handles
    var graphics_queue: c.VkQueue = undefined;
    var present_queue: c.VkQueue = undefined;
    vkGetDeviceQueue(device, graphics_family, 0, &graphics_queue);
    vkGetDeviceQueue(device, present_family, 0, &present_queue);

    std.debug.print("Logical device created successfully\n", .{});

    // Swapchain creation
    const GetPhysicalDeviceSurfaceCapabilitiesKHRFn = *const fn (
        c.VkPhysicalDevice,
        c.VkSurfaceKHR,
        *c.VkSurfaceCapabilitiesKHR,
    ) callconv(std.builtin.CallingConvention.c) c.VkResult;

    const GetPhysicalDeviceSurfaceFormatsKHRFn = *const fn (
        c.VkPhysicalDevice,
        c.VkSurfaceKHR,
        *u32,
        ?[*]c.VkSurfaceFormatKHR,
    ) callconv(std.builtin.CallingConvention.c) c.VkResult;

    const GetPhysicalDeviceSurfacePresentModesKHRFn = *const fn (
        c.VkPhysicalDevice,
        c.VkSurfaceKHR,
        *u32,
        ?[*]c.VkPresentModeKHR,
    ) callconv(std.builtin.CallingConvention.c) c.VkResult;

    const CreateSwapchainKHRFn = *const fn (
        c.VkDevice,
        [*c]const c.VkSwapchainCreateInfoKHR,
        ?*const c.VkAllocationCallbacks,
        *c.VkSwapchainKHR,
    ) callconv(std.builtin.CallingConvention.c) c.VkResult;

    const DestroySwapchainKHRFn = *const fn (
        c.VkDevice,
        c.VkSwapchainKHR,
        ?*const c.VkAllocationCallbacks,
    ) callconv(std.builtin.CallingConvention.c) void;

    const GetSwapchainImagesKHRFn = *const fn (
        c.VkDevice,
        c.VkSwapchainKHR,
        *u32,
        ?[*]c.VkImage,
    ) callconv(std.builtin.CallingConvention.c) c.VkResult;

    const CreateImageViewFn = *const fn (
        c.VkDevice,
        [*c]const c.VkImageViewCreateInfo,
        ?*const c.VkAllocationCallbacks,
        *c.VkImageView,
    ) callconv(std.builtin.CallingConvention.c) c.VkResult;

    const DestroyImageViewFn = *const fn (
        c.VkDevice,
        c.VkImageView,
        ?*const c.VkAllocationCallbacks,
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
    var surface_capabilities: c.VkSurfaceCapabilitiesKHR = undefined;
    if (vkGetPhysicalDeviceSurfaceCapabilitiesKHR(selected_device, surface, &surface_capabilities) != c.VK_SUCCESS) {
        std.debug.print("Failed to get surface capabilities\n", .{});
        return error.SurfaceCapabilitiesFailed;
    }

    // Query surface formats
    var format_count: u32 = 0;
    if (vkGetPhysicalDeviceSurfaceFormatsKHR(selected_device, surface, &format_count, null) != c.VK_SUCCESS) {
        std.debug.print("Failed to get surface format count\n", .{});
        return error.SurfaceFormatsFailed;
    }

    const surface_formats = try allocator.alloc(c.VkSurfaceFormatKHR, format_count);
    defer allocator.free(surface_formats);

    if (vkGetPhysicalDeviceSurfaceFormatsKHR(selected_device, surface, &format_count, surface_formats.ptr) != c.VK_SUCCESS) {
        std.debug.print("Failed to get surface formats\n", .{});
        return error.SurfaceFormatsFailed;
    }

    // Query present modes
    var present_mode_count: u32 = 0;
    if (vkGetPhysicalDeviceSurfacePresentModesKHR(selected_device, surface, &present_mode_count, null) != c.VK_SUCCESS) {
        std.debug.print("Failed to get present mode count\n", .{});
        return error.PresentModesFailed;
    }

    const present_modes = try allocator.alloc(c.VkPresentModeKHR, present_mode_count);
    defer allocator.free(present_modes);

    if (vkGetPhysicalDeviceSurfacePresentModesKHR(selected_device, surface, &present_mode_count, present_modes.ptr) != c.VK_SUCCESS) {
        std.debug.print("Failed to get present modes\n", .{});
        return error.PresentModesFailed;
    }

    // Choose surface format (prefer SRGB8888 with BGRA or RGBA)
    var surface_format: c.VkSurfaceFormatKHR = undefined;
    if (format_count == 1 and surface_formats[0].format == c.VK_FORMAT_UNDEFINED) {
        // Any format is allowed
        surface_format = c.VkSurfaceFormatKHR{
            .format = c.VK_FORMAT_B8G8R8A8_SRGB,
            .colorSpace = c.VK_COLOR_SPACE_SRGB_NONLINEAR_KHR,
        };
    } else {
        // Look for SRGB8888
        var found = false;
        for (surface_formats[0..format_count]) |fmt| {
            if (fmt.format == c.VK_FORMAT_B8G8R8A8_SRGB and fmt.colorSpace == c.VK_COLOR_SPACE_SRGB_NONLINEAR_KHR) {
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
    var present_mode: c.VkPresentModeKHR = c.VK_PRESENT_MODE_FIFO_KHR; // Always supported
    for (present_modes[0..present_mode_count]) |mode| {
        if (mode == c.VK_PRESENT_MODE_MAILBOX_KHR) {
            present_mode = mode;
            break;
        }
    }

    // Choose swap extent (swapchain dimensions)
    var extent: c.VkExtent2D = undefined;
    if (surface_capabilities.currentExtent.width != 0xFFFFFFFF) {
        extent = surface_capabilities.currentExtent;
    } else {
        extent = c.VkExtent2D{
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
    const swapchain_info = c.VkSwapchainCreateInfoKHR{
        .sType = c.VK_STRUCTURE_TYPE_SWAPCHAIN_CREATE_INFO_KHR,
        .surface = surface,
        .minImageCount = image_count,
        .imageFormat = surface_format.format,
        .imageColorSpace = surface_format.colorSpace,
        .imageExtent = extent,
        .imageArrayLayers = 1,
        .imageUsage = c.VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT,
        .preTransform = surface_capabilities.currentTransform,
        .compositeAlpha = c.VK_COMPOSITE_ALPHA_OPAQUE_BIT_KHR,
        .presentMode = present_mode,
        .clipped = c.VK_TRUE,
        .oldSwapchain = null,
    };

    // Handle sharing mode for queue families
    var swapchain_info_ptr = swapchain_info;
    var queue_family_indices: [2]u32 = undefined;

    if (same_family) {
        swapchain_info_ptr.imageSharingMode = c.VK_SHARING_MODE_EXCLUSIVE;
    } else {
        swapchain_info_ptr.imageSharingMode = c.VK_SHARING_MODE_CONCURRENT;
        swapchain_info_ptr.queueFamilyIndexCount = 2;
        queue_family_indices[0] = graphics_family;
        queue_family_indices[1] = present_family;
        swapchain_info_ptr.pQueueFamilyIndices = &queue_family_indices;
    }

    var swapchain: c.VkSwapchainKHR = undefined;
    if (vkCreateSwapchainKHR(device, &swapchain_info_ptr, null, &swapchain) != c.VK_SUCCESS) {
        std.debug.print("Failed to create swapchain\n", .{});
        return error.SwapchainCreationFailed;
    }
    defer vkDestroySwapchainKHR(device, swapchain, null);

    std.debug.print("Swapchain created: {}x{} format={}, present_mode={}, images={}\n", .{
        extent.width, extent.height, surface_format.format, present_mode, image_count,
    });

    // Get swapchain images
    var swapchain_image_count: u32 = 0;
    if (vkGetSwapchainImagesKHR(device, swapchain, &swapchain_image_count, null) != c.VK_SUCCESS) {
        std.debug.print("Failed to get swapchain image count\n", .{});
        return error.SwapchainImagesFailed;
    }

    const swapchain_images = try allocator.alloc(c.VkImage, swapchain_image_count);
    defer allocator.free(swapchain_images);

    if (vkGetSwapchainImagesKHR(device, swapchain, &swapchain_image_count, swapchain_images.ptr) != c.VK_SUCCESS) {
        std.debug.print("Failed to get swapchain images\n", .{});
        return error.SwapchainImagesFailed;
    }

    // Create image views for each swapchain image
    const swapchain_image_views = try allocator.alloc(c.VkImageView, swapchain_image_count);
    defer {
        for (swapchain_image_views[0..swapchain_image_count]) |view| {
            vkDestroyImageView(device, view, null);
        }
        allocator.free(swapchain_image_views);
    }

    for (swapchain_images[0..swapchain_image_count], 0..) |img, i| {
        const view_info = c.VkImageViewCreateInfo{
            .sType = c.VK_STRUCTURE_TYPE_IMAGE_VIEW_CREATE_INFO,
            .image = img,
            .viewType = c.VK_IMAGE_VIEW_TYPE_2D,
            .format = surface_format.format,
            .subresourceRange = c.VkImageSubresourceRange{
                .aspectMask = c.VK_IMAGE_ASPECT_COLOR_BIT,
                .baseMipLevel = 0,
                .levelCount = 1,
                .baseArrayLayer = 0,
                .layerCount = 1,
            },
        };

        if (vkCreateImageView(device, &view_info, null, &swapchain_image_views[i]) != c.VK_SUCCESS) {
            std.debug.print("Failed to create image view {}\n", .{i});
            return error.ImageViewCreationFailed;
        }
    }

    std.debug.print("Created {} image views\n", .{swapchain_image_count});

    // Shader modules creation
    const DestroyShaderModuleFn = *const fn (
        c.VkDevice,
        c.VkShaderModule,
        ?*const c.VkAllocationCallbacks,
    ) callconv(std.builtin.CallingConvention.c) void;

    const CreateShaderModuleFn = *const fn (
        c.VkDevice,
        [*c]const c.VkShaderModuleCreateInfo,
        ?*const c.VkAllocationCallbacks,
        *c.VkShaderModule,
    ) callconv(std.builtin.CallingConvention.c) c.VkResult;

    const vkCreateShaderModule: CreateShaderModuleFn =
        loadVulkanFunc(CreateShaderModuleFn, instance, "vkCreateShaderModule");

    const vkDestroyShaderModule: DestroyShaderModuleFn =
        loadVulkanFunc(DestroyShaderModuleFn, instance, "vkDestroyShaderModule");

    // Embed SPIR-V bytecode
    const vert_spirv = @embedFile("shaders/triangle.vert.spv");
    const frag_spirv = @embedFile("shaders/triangle.frag.spv");

    // Create vertex shader module
    const vert_info = c.VkShaderModuleCreateInfo{
        .sType = c.VK_STRUCTURE_TYPE_SHADER_MODULE_CREATE_INFO,
        .codeSize = vert_spirv.len,
        .pCode = @ptrCast(@alignCast(vert_spirv)),
    };

    var vert_shader_module: c.VkShaderModule = undefined;
    if (vkCreateShaderModule(device, &vert_info, null, &vert_shader_module) != c.VK_SUCCESS) {
        std.debug.print("Failed to create vertex shader module\n", .{});
        return error.VertexShaderModuleFailed;
    }
    defer vkDestroyShaderModule(device, vert_shader_module, null);

    // Create fragment shader module
    const frag_info = c.VkShaderModuleCreateInfo{
        .sType = c.VK_STRUCTURE_TYPE_SHADER_MODULE_CREATE_INFO,
        .codeSize = frag_spirv.len,
        .pCode = @ptrCast(@alignCast(frag_spirv)),
    };

    var frag_shader_module: c.VkShaderModule = undefined;
    if (vkCreateShaderModule(device, &frag_info, null, &frag_shader_module) != c.VK_SUCCESS) {
        std.debug.print("Failed to create fragment shader module\n", .{});
        return error.FragmentShaderModuleFailed;
    }
    defer vkDestroyShaderModule(device, frag_shader_module, null);

    std.debug.print("Shader modules created successfully\n", .{});

    // Render pass creation
    const CreateRenderPassFn = *const fn (
        c.VkDevice,
        [*c]const c.VkRenderPassCreateInfo,
        ?*const c.VkAllocationCallbacks,
        *c.VkRenderPass,
    ) callconv(std.builtin.CallingConvention.c) c.VkResult;

    const DestroyRenderPassFn = *const fn (
        c.VkDevice,
        c.VkRenderPass,
        ?*const c.VkAllocationCallbacks,
    ) callconv(std.builtin.CallingConvention.c) void;

    const vkCreateRenderPass: CreateRenderPassFn =
        loadVulkanFunc(CreateRenderPassFn, instance, "vkCreateRenderPass");

    const vkDestroyRenderPass: DestroyRenderPassFn =
        loadVulkanFunc(DestroyRenderPassFn, instance, "vkDestroyRenderPass");

    // Color attachment
    const color_attachment = c.VkAttachmentDescription{
        .format = surface_format.format,
        .samples = c.VK_SAMPLE_COUNT_1_BIT,
        .loadOp = c.VK_ATTACHMENT_LOAD_OP_CLEAR,
        .storeOp = c.VK_ATTACHMENT_STORE_OP_STORE,
        .stencilLoadOp = c.VK_ATTACHMENT_LOAD_OP_DONT_CARE,
        .stencilStoreOp = c.VK_ATTACHMENT_STORE_OP_DONT_CARE,
        .initialLayout = c.VK_IMAGE_LAYOUT_UNDEFINED,
        .finalLayout = c.VK_IMAGE_LAYOUT_PRESENT_SRC_KHR,
    };

    const color_attachment_ref = c.VkAttachmentReference{
        .attachment = 0,
        .layout = c.VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL,
    };

    const subpass = c.VkSubpassDescription{
        .pipelineBindPoint = c.VK_PIPELINE_BIND_POINT_GRAPHICS,
        .colorAttachmentCount = 1,
        .pColorAttachments = &color_attachment_ref,
    };

    const dependency = c.VkSubpassDependency{
        .srcSubpass = c.VK_SUBPASS_EXTERNAL,
        .dstSubpass = 0,
        .srcStageMask = c.VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT,
        .srcAccessMask = 0,
        .dstStageMask = c.VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT,
        .dstAccessMask = c.VK_ACCESS_COLOR_ATTACHMENT_WRITE_BIT,
    };

    const render_pass_info = c.VkRenderPassCreateInfo{
        .sType = c.VK_STRUCTURE_TYPE_RENDER_PASS_CREATE_INFO,
        .attachmentCount = 1,
        .pAttachments = &color_attachment,
        .subpassCount = 1,
        .pSubpasses = &subpass,
        .dependencyCount = 1,
        .pDependencies = &dependency,
    };

    var render_pass: c.VkRenderPass = undefined;
    if (vkCreateRenderPass(device, &render_pass_info, null, &render_pass) != c.VK_SUCCESS) {
        std.debug.print("Failed to create render pass\n", .{});
        return error.RenderPassCreationFailed;
    }
    defer vkDestroyRenderPass(device, render_pass, null);

    std.debug.print("Render pass created successfully\n", .{});

    // Framebuffer creation
    const CreateFramebufferFn = *const fn (
        c.VkDevice,
        [*c]const c.VkFramebufferCreateInfo,
        ?*const c.VkAllocationCallbacks,
        *c.VkFramebuffer,
    ) callconv(std.builtin.CallingConvention.c) c.VkResult;

    const DestroyFramebufferFn = *const fn (
        c.VkDevice,
        c.VkFramebuffer,
        ?*const c.VkAllocationCallbacks,
    ) callconv(std.builtin.CallingConvention.c) void;

    const vkCreateFramebuffer: CreateFramebufferFn =
        loadVulkanFunc(CreateFramebufferFn, instance, "vkCreateFramebuffer");

    const vkDestroyFramebuffer: DestroyFramebufferFn =
        loadVulkanFunc(DestroyFramebufferFn, instance, "vkDestroyFramebuffer");

    const framebuffers = try allocator.alloc(c.VkFramebuffer, swapchain_image_count);
    defer {
        for (framebuffers[0..swapchain_image_count]) |fb| {
            vkDestroyFramebuffer(device, fb, null);
        }
        allocator.free(framebuffers);
    }

    for (swapchain_image_views[0..swapchain_image_count], 0..) |view, i| {
        const framebuffer_info = c.VkFramebufferCreateInfo{
            .sType = c.VK_STRUCTURE_TYPE_FRAMEBUFFER_CREATE_INFO,
            .renderPass = render_pass,
            .attachmentCount = 1,
            .pAttachments = &view,
            .width = extent.width,
            .height = extent.height,
            .layers = 1,
        };

        if (vkCreateFramebuffer(device, &framebuffer_info, null, &framebuffers[i]) != c.VK_SUCCESS) {
            std.debug.print("Failed to create framebuffer {}\n", .{i});
            return error.FramebufferCreationFailed;
        }
    }

    std.debug.print("Created {} framebuffers\n", .{swapchain_image_count});

    // Command pool and command buffers
    const CreateCommandPoolFn = *const fn (
        c.VkDevice,
        [*c]const c.VkCommandPoolCreateInfo,
        ?*const c.VkAllocationCallbacks,
        *c.VkCommandPool,
    ) callconv(std.builtin.CallingConvention.c) c.VkResult;

    const DestroyCommandPoolFn = *const fn (
        c.VkDevice,
        c.VkCommandPool,
        ?*const c.VkAllocationCallbacks,
    ) callconv(std.builtin.CallingConvention.c) void;

    const AllocateCommandBuffersFn = *const fn (
        c.VkDevice,
        [*c]const c.VkCommandBufferAllocateInfo,
        [*]c.VkCommandBuffer,
    ) callconv(std.builtin.CallingConvention.c) c.VkResult;

    const FreeCommandBuffersFn = *const fn (
        c.VkDevice,
        c.VkCommandPool,
        u32,
        [*]const c.VkCommandBuffer,
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
    const command_pool_info = c.VkCommandPoolCreateInfo{
        .sType = c.VK_STRUCTURE_TYPE_COMMAND_POOL_CREATE_INFO,
        .queueFamilyIndex = graphics_family,
        .flags = c.VK_COMMAND_POOL_CREATE_RESET_COMMAND_BUFFER_BIT,
    };

    var command_pool: c.VkCommandPool = undefined;
    if (vkCreateCommandPool(device, &command_pool_info, null, &command_pool) != c.VK_SUCCESS) {
        std.debug.print("Failed to create command pool\n", .{});
        return error.CommandPoolCreationFailed;
    }
    defer vkDestroyCommandPool(device, command_pool, null);

    // Allocate command buffers (one per framebuffer)
    const command_buffers = try allocator.alloc(c.VkCommandBuffer, swapchain_image_count);
    defer {
        vkFreeCommandBuffers(device, command_pool, swapchain_image_count, command_buffers.ptr);
        allocator.free(command_buffers);
    }

    const cmd_alloc_info = c.VkCommandBufferAllocateInfo{
        .sType = c.VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO,
        .commandPool = command_pool,
        .level = c.VK_COMMAND_BUFFER_LEVEL_PRIMARY,
        .commandBufferCount = swapchain_image_count,
    };

    if (vkAllocateCommandBuffers(device, &cmd_alloc_info, command_buffers.ptr) != c.VK_SUCCESS) {
        std.debug.print("Failed to allocate command buffers\n", .{});
        return error.CommandBufferAllocationFailed;
    }

    std.debug.print("Allocated {} command buffers\n", .{swapchain_image_count});

    // Graphics pipeline creation
    const CreatePipelineLayoutFn = *const fn (
        c.VkDevice,
        [*c]const c.VkPipelineLayoutCreateInfo,
        ?*const c.VkAllocationCallbacks,
        *c.VkPipelineLayout,
    ) callconv(std.builtin.CallingConvention.c) c.VkResult;

    const DestroyPipelineLayoutFn = *const fn (
        c.VkDevice,
        c.VkPipelineLayout,
        ?*const c.VkAllocationCallbacks,
    ) callconv(std.builtin.CallingConvention.c) void;

    const CreateGraphicsPipelinesFn = *const fn (
        c.VkDevice,
        c.VkPipelineCache,
        u32,
        [*c]const c.VkGraphicsPipelineCreateInfo,
        ?*const c.VkAllocationCallbacks,
        [*]c.VkPipeline,
    ) callconv(std.builtin.CallingConvention.c) c.VkResult;

    const DestroyPipelineFn = *const fn (
        c.VkDevice,
        c.VkPipeline,
        ?*const c.VkAllocationCallbacks,
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
    const pipeline_layout_info = c.VkPipelineLayoutCreateInfo{
        .sType = c.VK_STRUCTURE_TYPE_PIPELINE_LAYOUT_CREATE_INFO,
    };

    var pipeline_layout: c.VkPipelineLayout = undefined;
    if (vkCreatePipelineLayout(device, &pipeline_layout_info, null, &pipeline_layout) != c.VK_SUCCESS) {
        std.debug.print("Failed to create pipeline layout\n", .{});
        return error.PipelineLayoutCreationFailed;
    }
    defer vkDestroyPipelineLayout(device, pipeline_layout, null);

    // Shader stages
    const vert_stage_info = c.VkPipelineShaderStageCreateInfo{
        .sType = c.VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO,
        .stage = c.VK_SHADER_STAGE_VERTEX_BIT,
        .module = vert_shader_module,
        .pName = "main",
    };

    const frag_stage_info = c.VkPipelineShaderStageCreateInfo{
        .sType = c.VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO,
        .stage = c.VK_SHADER_STAGE_FRAGMENT_BIT,
        .module = frag_shader_module,
        .pName = "main",
    };

    const shader_stages = [_]c.VkPipelineShaderStageCreateInfo{ vert_stage_info, frag_stage_info };

    // Vertex input state (no vertex buffers for now, hardcoded in shader)
    const vertex_input_info = c.VkPipelineVertexInputStateCreateInfo{
        .sType = c.VK_STRUCTURE_TYPE_PIPELINE_VERTEX_INPUT_STATE_CREATE_INFO,
    };

    // Input assembly
    const input_assembly = c.VkPipelineInputAssemblyStateCreateInfo{
        .sType = c.VK_STRUCTURE_TYPE_PIPELINE_INPUT_ASSEMBLY_STATE_CREATE_INFO,
        .topology = c.VK_PRIMITIVE_TOPOLOGY_TRIANGLE_LIST,
        .primitiveRestartEnable = c.VK_FALSE,
    };

    // Viewport and scissor
    const viewport = c.VkViewport{
        .x = 0.0,
        .y = 0.0,
        .width = @floatFromInt(extent.width),
        .height = @floatFromInt(extent.height),
        .minDepth = 0.0,
        .maxDepth = 1.0,
    };

    const scissor = c.VkRect2D{
        .offset = .{ .x = 0, .y = 0 },
        .extent = extent,
    };

    const viewport_state = c.VkPipelineViewportStateCreateInfo{
        .sType = c.VK_STRUCTURE_TYPE_PIPELINE_VIEWPORT_STATE_CREATE_INFO,
        .viewportCount = 1,
        .pViewports = &viewport,
        .scissorCount = 1,
        .pScissors = &scissor,
    };

    // Rasterizer
    const rasterizer = c.VkPipelineRasterizationStateCreateInfo{
        .sType = c.VK_STRUCTURE_TYPE_PIPELINE_RASTERIZATION_STATE_CREATE_INFO,
        .depthClampEnable = c.VK_FALSE,
        .rasterizerDiscardEnable = c.VK_FALSE,
        .polygonMode = c.VK_POLYGON_MODE_FILL,
        .cullMode = c.VK_CULL_MODE_NONE,
        .frontFace = c.VK_FRONT_FACE_CLOCKWISE,
        .depthBiasEnable = c.VK_FALSE,
        .lineWidth = 1.0,
    };

    // Multisampling (no MSAA)
    const multisampling = c.VkPipelineMultisampleStateCreateInfo{
        .sType = c.VK_STRUCTURE_TYPE_PIPELINE_MULTISAMPLE_STATE_CREATE_INFO,
        .rasterizationSamples = c.VK_SAMPLE_COUNT_1_BIT,
        .sampleShadingEnable = c.VK_FALSE,
    };

    // Color blending (no blending, write all channels)
    const color_blend_attachment = c.VkPipelineColorBlendAttachmentState{
        .colorWriteMask = c.VK_COLOR_COMPONENT_R_BIT | c.VK_COLOR_COMPONENT_G_BIT | c.VK_COLOR_COMPONENT_B_BIT | c.VK_COLOR_COMPONENT_A_BIT,
        .blendEnable = c.VK_FALSE,
    };

    const color_blending = c.VkPipelineColorBlendStateCreateInfo{
        .sType = c.VK_STRUCTURE_TYPE_PIPELINE_COLOR_BLEND_STATE_CREATE_INFO,
        .logicOpEnable = c.VK_FALSE,
        .attachmentCount = 1,
        .pAttachments = &color_blend_attachment,
    };

    // Dynamic state (none for now)
    const pipeline_info = c.VkGraphicsPipelineCreateInfo{
        .sType = c.VK_STRUCTURE_TYPE_GRAPHICS_PIPELINE_CREATE_INFO,
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

    var pipeline: c.VkPipeline = undefined;
    if (vkCreateGraphicsPipelines(device, null, 1, &pipeline_info, null, @ptrCast(&pipeline)) != c.VK_SUCCESS) {
        std.debug.print("Failed to create graphics pipeline\n", .{});
        return error.PipelineCreationFailed;
    }
    defer vkDestroyPipeline(device, pipeline, null);

    std.debug.print("Graphics pipeline created successfully\n", .{});

    // Record command buffers
    const BeginCommandBufferFn = *const fn (
        c.VkCommandBuffer,
        [*c]const c.VkCommandBufferBeginInfo,
    ) callconv(std.builtin.CallingConvention.c) c.VkResult;

    const EndCommandBufferFn = *const fn (
        c.VkCommandBuffer,
    ) callconv(std.builtin.CallingConvention.c) c.VkResult;

    const CmdBeginRenderPassFn = *const fn (
        c.VkCommandBuffer,
        [*c]const c.VkRenderPassBeginInfo,
        c.VkSubpassContents,
    ) callconv(std.builtin.CallingConvention.c) void;

    const CmdBindPipelineFn = *const fn (
        c.VkCommandBuffer,
        c.VkPipelineBindPoint,
        c.VkPipeline,
    ) callconv(std.builtin.CallingConvention.c) void;

    const CmdDrawFn = *const fn (
        c.VkCommandBuffer,
        u32,
        u32,
        u32,
        u32,
    ) callconv(std.builtin.CallingConvention.c) void;

    const CmdEndRenderPassFn = *const fn (
        c.VkCommandBuffer,
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

    const clear_color = c.VkClearValue{ .color = .{ .float32 = .{ 0.0, 0.0, 0.0, 1.0 } } };

    for (command_buffers[0..swapchain_image_count], 0..) |cmd, i| {
        const begin_info = c.VkCommandBufferBeginInfo{
            .sType = c.VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO,
            .flags = c.VK_COMMAND_BUFFER_USAGE_SIMULTANEOUS_USE_BIT,
        };

        if (vkBeginCommandBuffer(cmd, &begin_info) != c.VK_SUCCESS) {
            std.debug.print("Failed to begin command buffer {}\n", .{i});
            return error.CommandBufferBeginFailed;
        }

        const rp_begin = c.VkRenderPassBeginInfo{
            .sType = c.VK_STRUCTURE_TYPE_RENDER_PASS_BEGIN_INFO,
            .renderPass = render_pass,
            .framebuffer = framebuffers[i],
            .renderArea = .{ .offset = .{ .x = 0, .y = 0 }, .extent = extent },
            .clearValueCount = 1,
            .pClearValues = &clear_color,
        };

        vkCmdBeginRenderPass(cmd, &rp_begin, c.VK_SUBPASS_CONTENTS_INLINE);
        vkCmdBindPipeline(cmd, c.VK_PIPELINE_BIND_POINT_GRAPHICS, pipeline);
        vkCmdDraw(cmd, 3, 1, 0, 0);
        vkCmdEndRenderPass(cmd);

        if (vkEndCommandBuffer(cmd) != c.VK_SUCCESS) {
            std.debug.print("Failed to end command buffer {}\n", .{i});
            return error.CommandBufferEndFailed;
        }
    }

    std.debug.print("Command buffers recorded successfully\n", .{});

    // Synchronization primitives
    const CreateSemaphoreFn = *const fn (
        c.VkDevice,
        [*c]const c.VkSemaphoreCreateInfo,
        ?*const c.VkAllocationCallbacks,
        *c.VkSemaphore,
    ) callconv(std.builtin.CallingConvention.c) c.VkResult;

    const DestroySemaphoreFn = *const fn (
        c.VkDevice,
        c.VkSemaphore,
        ?*const c.VkAllocationCallbacks,
    ) callconv(std.builtin.CallingConvention.c) void;

    const CreateFenceFn = *const fn (
        c.VkDevice,
        [*c]const c.VkFenceCreateInfo,
        ?*const c.VkAllocationCallbacks,
        *c.VkFence,
    ) callconv(std.builtin.CallingConvention.c) c.VkResult;

    const DestroyFenceFn = *const fn (
        c.VkDevice,
        c.VkFence,
        ?*const c.VkAllocationCallbacks,
    ) callconv(std.builtin.CallingConvention.c) void;

    const WaitForFencesFn = *const fn (
        c.VkDevice,
        u32,
        [*]const c.VkFence,
        c.VkBool32,
        u64,
    ) callconv(std.builtin.CallingConvention.c) c.VkResult;

    const ResetFencesFn = *const fn (
        c.VkDevice,
        u32,
        [*]const c.VkFence,
    ) callconv(std.builtin.CallingConvention.c) c.VkResult;

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

    var image_available: c.VkSemaphore = undefined;
    var render_finished: c.VkSemaphore = undefined;
    var in_flight_fence: c.VkFence = undefined;

    const semaphore_info = c.VkSemaphoreCreateInfo{
        .sType = c.VK_STRUCTURE_TYPE_SEMAPHORE_CREATE_INFO,
    };

    if (vkCreateSemaphore(device, &semaphore_info, null, &image_available) != c.VK_SUCCESS or
        vkCreateSemaphore(device, &semaphore_info, null, &render_finished) != c.VK_SUCCESS) {
        std.debug.print("Failed to create semaphores\n", .{});
        return error.SemaphoreCreationFailed;
    }
    defer vkDestroySemaphore(device, image_available, null);
    defer vkDestroySemaphore(device, render_finished, null);

    const fence_info = c.VkFenceCreateInfo{
        .sType = c.VK_STRUCTURE_TYPE_FENCE_CREATE_INFO,
        .flags = c.VK_FENCE_CREATE_SIGNALED_BIT, // Start signaled so first frame can proceed
    };

    if (vkCreateFence(device, &fence_info, null, &in_flight_fence) != c.VK_SUCCESS) {
        std.debug.print("Failed to create fence\n", .{});
        return error.FenceCreationFailed;
    }
    defer vkDestroyFence(device, in_flight_fence, null);

    std.debug.print("Synchronization primitives created\n", .{});

    // Load queue submission and presentation functions
    const QueueSubmitFn = *const fn (
        c.VkQueue,
        u32,
        [*]const c.VkSubmitInfo,
        c.VkFence,
    ) callconv(std.builtin.CallingConvention.c) c.VkResult;

    const QueuePresentKHRFn = *const fn (
        c.VkQueue,
        [*]const c.VkPresentInfoKHR,
    ) callconv(std.builtin.CallingConvention.c) c.VkResult;

    const vkQueueSubmit: QueueSubmitFn =
        loadVulkanFunc(QueueSubmitFn, instance, "vkQueueSubmit");

    const vkQueuePresentKHR: QueuePresentKHRFn =
        loadVulkanFunc(QueuePresentKHRFn, instance, "vkQueuePresentKHR");

    std.debug.print("Starting render loop...\n", .{});

    // Main loop
    while (c.glfwWindowShouldClose(window) == 0) {
        c.glfwPollEvents();

        // Wait for previous frame to finish
        _ = vkWaitForFences(device, 1, @ptrCast(&in_flight_fence), c.VK_TRUE, ~@as(u64, 0));
        _ = vkResetFences(device, 1, @ptrCast(&in_flight_fence));

        // Acquire next swapchain image
        var image_index: u32 = undefined;
        if (c.vkAcquireNextImageKHR(device, swapchain, ~@as(u64, 0), image_available, null, &image_index) != c.VK_SUCCESS) {
            continue;
        }

        // Submit command buffer
        const submit_info = c.VkSubmitInfo{
            .sType = c.VK_STRUCTURE_TYPE_SUBMIT_INFO,
            .waitSemaphoreCount = 1,
            .pWaitSemaphores = &image_available,
            .pWaitDstStageMask = &[_]c.VkPipelineStageFlags{c.VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT},
            .commandBufferCount = 1,
            .pCommandBuffers = &command_buffers[image_index],
            .signalSemaphoreCount = 1,
            .pSignalSemaphores = &render_finished,
        };

        if (vkQueueSubmit(graphics_queue, 1, @ptrCast(&submit_info), in_flight_fence) != c.VK_SUCCESS) {
            std.debug.print("Failed to submit draw command buffer\n", .{});
            break;
        }

        // Present
        const present_info = c.VkPresentInfoKHR{
            .sType = c.VK_STRUCTURE_TYPE_PRESENT_INFO_KHR,
            .waitSemaphoreCount = 1,
            .pWaitSemaphores = &render_finished,
            .swapchainCount = 1,
            .pSwapchains = &swapchain,
            .pImageIndices = &image_index,
        };

        _ = vkQueuePresentKHR(present_queue, @ptrCast(&present_info));
    }
}
