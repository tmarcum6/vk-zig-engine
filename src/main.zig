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

    // Main loop
    while (c.glfwWindowShouldClose(window) == 0) {
        c.glfwPollEvents();
    }
}
