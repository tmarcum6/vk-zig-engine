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

    // Main loop
    while (c.glfwWindowShouldClose(window) == 0) {
        c.glfwPollEvents();
    }
}
