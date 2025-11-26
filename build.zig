const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Dependencies
    const raylib_dep = b.dependency("raylib", .{
        .target = target,
        .optimize = optimize,
    });
    const entt_dep = b.dependency("entt", .{
        .target = target,
        .optimize = optimize,
    });
    const entt_mod = entt_dep.module("zig-ecs");

    // Modules
    
    // Raylib Wrapper Module
    const raylib_wrapper_mod = b.createModule(.{
        .root_source_file = b.path("src/core/raylib.zig"),
        .target = target,
        .optimize = optimize,
    });
    raylib_wrapper_mod.addIncludePath(raylib_dep.path("src"));

    // 1. Core (Universal utilities + External libs)
    const core_mod = b.createModule(.{
        .root_source_file = b.path("src/core/mod.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "entt", .module = entt_mod },
            .{ .name = "raylib.zig", .module = raylib_wrapper_mod },
        },
    });

    // 2. Circuit (Simulation Logic & Data)
    const circuit_mod = b.createModule(.{
        .root_source_file = b.path("src/circuit/mod.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "core", .module = core_mod },
        },
    });

    // 3. Editor (Tooling Logic & State)
    const editor_mod = b.createModule(.{
        .root_source_file = b.path("src/editor/mod.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "core", .module = core_mod },
            .{ .name = "circuit", .module = circuit_mod },
        },
    });

    // 4. Gfx (Rendering)
    const gfx_mod = b.createModule(.{
        .root_source_file = b.path("src/gfx/mod.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "core", .module = core_mod },
            .{ .name = "circuit", .module = circuit_mod },
            .{ .name = "editor", .module = editor_mod },
        },
    });

    // 5. App (Integration)
    const app_mod = b.createModule(.{
        .root_source_file = b.path("src/app.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "core", .module = core_mod },
            .{ .name = "circuit", .module = circuit_mod },
            .{ .name = "editor", .module = editor_mod },
            .{ .name = "gfx", .module = gfx_mod },
        },
    });

    // Executable
    const exe_mod = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    exe_mod.addImport("app", app_mod);

    const exe = b.addExecutable(.{
        .name = "zlogic",
        .root_module = exe_mod,
    });
    
    // Link Raylib to the final executable
    exe.linkLibrary(raylib_dep.artifact("raylib"));

    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);
}
