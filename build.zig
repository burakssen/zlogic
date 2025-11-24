const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const raylib_dep = b.dependency("raylib", .{
        .target = target,
        .optimize = optimize,
    });

    const raylib_mod = b.createModule(.{
        .root_source_file = b.path("src/raylib.zig"),
        .target = target,
        .optimize = optimize,
    });

    raylib_mod.linkLibrary(raylib_dep.artifact("raylib"));
    raylib_mod.addIncludePath(raylib_dep.path("src"));

    const entt_dep = b.dependency("entt", .{
        .target = target,
        .optimize = optimize,
    });

    const entt_mod = entt_dep.module("zig-ecs");

    const app_mod = b.createModule(.{
        .root_source_file = b.path("src/app/app.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "raylib", .module = raylib_mod },
            .{ .name = "entt", .module = entt_mod },
        },
    });

    const exe_mod = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "app", .module = app_mod },
        },
    });

    const exe = b.addExecutable(.{
        .name = "zlogic",
        .root_module = exe_mod,
    });

    b.installArtifact(exe);

    const run_step = b.step("run", "Run the program");
    const run_cmd = b.addRunArtifact(exe);
    run_step.dependOn(&run_cmd.step);

    const test_step = b.step("test", "Run the tests");
    const test_cmd = b.addTest(.{
        .root_module = exe_mod,
    });
    test_step.dependOn(&test_cmd.step);
}
