const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

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

    // ImGui C++ wrapper library (platform + renderer backends)
    const imgui_wrapper_mod = b.createModule(.{
        .target = target,
        .optimize = optimize,
        .link_libc = true,
        .link_libcpp = true,
    });
    const imgui_cpp_sources = [_][]const u8{
        "src/imgui_wrapper/imgui_wrapper.cpp",
        "src/imgui_impl/imgui_impl_glfw.cpp",
        "src/imgui_impl/imgui_impl_vulkan.cpp",
    };
    for (imgui_cpp_sources) |src| {
        imgui_wrapper_mod.addCSourceFile(.{
            .file = b.path(src),
            .flags = &.{"-std=c++17"},
        });
    }
    // Add ImGui core sources from cimgui package
    const imgui_core_sources = [_][]const u8{
        "imgui.cpp",
        "imgui_draw.cpp",
        "imgui_tables.cpp",
        "imgui_widgets.cpp",
    };
    for (imgui_core_sources) |src| {
        imgui_wrapper_mod.addCSourceFile(.{
            .file = cimgui_dep.path(b.fmt("src-docking/{s}", .{src})),
            .flags = &.{"-std=c++17"},
        });
    }
    imgui_wrapper_mod.addIncludePath(b.path("src/imgui_impl"));
    imgui_wrapper_mod.addIncludePath(cimgui_dep.path("src-docking"));
    imgui_wrapper_mod.addSystemIncludePath(glfw_dep.path("glfw/include"));
    imgui_wrapper_mod.addSystemIncludePath(.{ .cwd_relative = "/opt/homebrew/Cellar/molten-vk/1.4.1/libexec/include" });
    imgui_wrapper_mod.linkLibrary(glfw_artifact);

    const imgui_wrapper_lib = b.addLibrary(.{
        .name = "imgui_wrapper",
        .root_module = imgui_wrapper_mod,
        .linkage = .static,
    });
    const imgui_wrapper_module = b.addTranslateC(.{
        .root_source_file = b.path("src/imgui_wrapper/imgui_wrapper.h"),
        .target = target,
        .optimize = optimize,
    });
    imgui_wrapper_module.addIncludePath(b.path("src/imgui_wrapper"));
    imgui_wrapper_module.addIncludePath(b.path("src/imgui_impl"));
    imgui_wrapper_module.addIncludePath(cimgui_dep.path("src-docking"));
    imgui_wrapper_module.addSystemIncludePath(glfw_dep.path("glfw/include"));
    imgui_wrapper_module.addSystemIncludePath(.{ .cwd_relative = "/opt/homebrew/Cellar/molten-vk/1.4.1/libexec/include" });
    const imgui_wrapper_c_module = imgui_wrapper_module.createModule();

    const exe = b.addExecutable(.{
        .name = "vk_zig_engine",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "glfw", .module = glfw_c_module },
                .{ .name = "vulkan_c", .module = vulkan_c_module },
                .{ .name = "imgui", .module = cimgui_module },
                .{ .name = "imgui_wrapper", .module = imgui_wrapper_c_module },
            },
        }),
    });

    exe.root_module.linkLibrary(glfw_artifact);
    exe.root_module.linkLibrary(cimgui_clib);
    exe.root_module.linkLibrary(imgui_wrapper_lib);

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
