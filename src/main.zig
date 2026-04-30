const std = @import("std");
const c = @import("c");

// Vulkan function loader using GLFW's vkGetInstanceProcAddress
fn loadVulkanFunc(comptime T: type, instance: c.VkInstance, name: [*c]const u8) T {
    const func = c.glfwGetInstanceProcAddress(instance, name);
    return @ptrCast(@alignCast(func));
}

pub fn main() !void {
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
    const allocator = std.heap.page_allocator;
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
        // Get queue family count
        var queue_family_count: u32 = 0;
        vkGetPhysicalDeviceQueueFamilyProperties(device, &queue_family_count, null);

        if (queue_family_count == 0) continue;

        // Allocate and get queue family properties
        const queue_families = try allocator.alloc(c.VkQueueFamilyProperties, queue_family_count);
        defer allocator.free(queue_families);
        vkGetPhysicalDeviceQueueFamilyProperties(device, &queue_family_count, queue_families.ptr);

        // Check each queue family
        for (queue_families, 0..) |props, i| {
            const family_idx: u32 = @intCast(i);

            // Check for graphics support
            if (props.queueFlags & c.VK_QUEUE_GRAPHICS_BIT != 0) {
                if (graphics_family == std.math.maxInt(u32)) {
                    graphics_family = family_idx;
                }
            }

            // Check for present support
            var present_support: c.VkBool32 = 0;
            if (vkGetPhysicalDeviceSurfaceSupportKHR(device, family_idx, surface, &present_support) == c.VK_SUCCESS) {
                if (present_support != 0 and present_family == std.math.maxInt(u32)) {
                    present_family = family_idx;
                }
            }
        }

        // If device has both graphics and present support, select it
        if (graphics_family != std.math.maxInt(u32) and present_family != std.math.maxInt(u32)) {
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
    if (same_family) {
        swapchain_info_ptr.imageSharingMode = c.VK_SHARING_MODE_EXCLUSIVE;
    } else {
        swapchain_info_ptr.imageSharingMode = c.VK_SHARING_MODE_CONCURRENT;
        swapchain_info_ptr.queueFamilyIndexCount = 2;
        var queue_family_indices = [_]u32{ graphics_family, present_family };
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

    // Main loop
    while (c.glfwWindowShouldClose(window) == 0) {
        c.glfwPollEvents();
    }
}
