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

    // GLFW C bindings (GLFW only)
    const glfw_c = b.addTranslateC(.{
        .root_source_file = b.path("src/headers/glfw.h"),
        .target = target,
        .optimize = optimize,
    });
    glfw_c.addSystemIncludePath(glfw_artifact.getEmittedIncludeTree());
    const glfw_c_module = glfw_c.createModule();

    // Vulkan C bindings (from MoltenVK headers)
    const vulkan_c = b.addTranslateC(.{
        .root_source_file = b.path("src/headers/vulkan.h"),
        .target = target,
        .optimize = optimize,
    });
    vulkan_c.addSystemIncludePath(.{ .cwd_relative = "/opt/homebrew/Cellar/molten-vk/1.4.1/libexec/include" });
    const vulkan_c_module = vulkan_c.createModule();

    // cimgui dependency (C bindings for ImGui - using docking branch)
    const cimgui_dep = b.dependency("cimgui", .{
        .target = target,
        .optimize = optimize,
    });
    const cimgui_module = cimgui_dep.module("cimgui_docking");
    const cimgui_clib = cimgui_dep.artifact("cimgui_docking_clib");

    // ImGui implementation files - TODO: Add proper C++ backend integration later

    const exe = b.addExecutable(.{
        .name = "vk_zig_engine",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "vulkan", .module = vulkan_module },
                .{ .name = "glfw", .module = glfw_c_module },
                .{ .name = "vulkan_c", .module = vulkan_c_module },
                .{ .name = "imgui", .module = cimgui_module },
            },
        }),
    });

    exe.root_module.linkLibrary(glfw_artifact);
    exe.root_module.linkLibrary(cimgui_clib);

    // macOS: Link MoltenVK for Vulkan support
    if (target.result.os.tag == .macos) {
        const brew_lib = b.path("lib_search");
        exe.root_module.addLibraryPath(brew_lib);
        exe.root_module.linkSystemLibrary("MoltenVK", .{});
    }

    // Shader compilation step (GLSL -> SPIR-V)
    const shaders_step = b.step("shaders", "Compile GLSL shaders to SPIR-V");

    const shader_sources = [_][]const u8{ "triangle.vert", "triangle.frag" };
    for (shader_sources) |src_name| {
        const src_path = b.pathJoin(&.{ "src", "shaders", src_name });
        const dst_path = b.pathJoin(&.{ "src", "shaders", b.fmt("{s}.spv", .{src_name}) });

        const compile = b.addSystemCommand(&[_][]const u8{ "glslangValidator", "-V", src_path, "-o", dst_path });
        compile.setName(b.fmt("compile {s}", .{src_name}));
        shaders_step.dependOn(&compile.step);
    }

    // Make install depend on shader compilation
    b.getInstallStep().dependOn(shaders_step);

    b.installArtifact(exe);

    const run_step = b.step("run", "Run the app");
    const run_cmd = b.addRunArtifact(exe);
    run_cmd.setEnvironmentVariable("VK_ICD_FILENAMES", "/opt/homebrew/share/vulkan/icd.d/MoltenVK_icd.json");
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
