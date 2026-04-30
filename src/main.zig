const std = @import("std");
const c = @import("c");

pub fn main() !void {
    // Initialize GLFW
    if (c.glfwInit() == 0) {
        std.debug.print("Failed to initialize GLFW\n", .{});
        return error.GlfwInitFailed;
    }
    defer c.glfwTerminate();

    // Check Vulkan support
    if (c.glfwVulkanSupported() == 0) {
        std.debug.print("Vulkan not supported by GLFW - install MoltenVK\n", .{});
        std.debug.print("Continuing without Vulkan for now...\n", .{});
    }

    // Window hints for Vulkan (no OpenGL context)
    c.glfwWindowHint(c.GLFW_CLIENT_API, c.GLFW_NO_API);

    // Create window
    const window = c.glfwCreateWindow(800, 600, "VK Zig Engine", null, null) orelse {
        std.debug.print("Failed to create window\n", .{});
        return error.WindowCreationFailed;
    };
    defer c.glfwDestroyWindow(window);

    std.debug.print("Window created successfully!\n", .{});
    std.debug.print("Vulkan is supported. Install MoltenVK to create Vulkan instance.\n", .{});

    // Main loop
    while (c.glfwWindowShouldClose(window) == 0) {
        c.glfwPollEvents();
    }
}

test "simple test" {
    const gpa = std.testing.allocator;
    var list = @TypeOf(std.ArrayList(i32).init(gpa)){};
    list = std.ArrayList(i32).init(gpa);
    defer list.deinit();
    try list.append(42);
    try std.testing.expectEqual(@as(i32, 42), list.pop());
}
