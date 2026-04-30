const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const vulkan_dep = b.dependency("vulkan", .{
        .target = target,
        .registry = b.path("registry/vk.xml"),
    });
    const vulkan_module = vulkan_dep.module("vulkan-zig");

    // GLFW dependency and C header translation
    const glfw_dep = b.dependency("glfw_zig", .{
        .target = target,
        .optimize = optimize,
    });
    const glfw_artifact = glfw_dep.artifact("glfw");

    const glfw_c = b.addTranslateC(.{
        .root_source_file = b.path("src/c/glfw.h"),
        .target = target,
        .optimize = optimize,
    });
    glfw_c.addSystemIncludePath(glfw_artifact.getEmittedIncludeTree());
    const glfw_c_module = glfw_c.createModule();

    const exe = b.addExecutable(.{
        .name = "vk_zig_engine",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "vulkan", .module = vulkan_module },
                .{ .name = "c", .module = glfw_c_module },
            },
        }),
    });

    exe.root_module.linkLibrary(glfw_artifact);

    b.installArtifact(exe);

    const run_step = b.step("run", "Run the app");
    const run_cmd = b.addRunArtifact(exe);
    run_step.dependOn(&run_cmd.step);
    run_cmd.step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const exe_tests = b.addTest(.{ .root_module = exe.root_module });
    const run_exe_tests = b.addRunArtifact(exe_tests);

    const test_step = b.step("test", "Run tests");
    test_step.dependOn(&run_exe_tests.step);
}
