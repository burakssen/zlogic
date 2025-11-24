const std = @import("std");
const builtin = @import("builtin");
const rl = @import("raylib").rl;

const App = @This();

allocator: std.mem.Allocator,
window_size: rl.Vector2,
window_title: []const u8,

pub fn init(
    allocator: std.mem.Allocator,
    window_size: rl.Vector2,
    window_title: []const u8,
) !*App {
    const app = try allocator.create(App);

    app.* = .{
        .allocator = allocator,
        .window_size = window_size,
        .window_title = window_title,
    };

    rl.InitWindow(
        @as(c_int, @intFromFloat(window_size.x)),
        @as(c_int, @intFromFloat(window_size.y)),
        window_title.ptr,
    );

    return app;
}

pub fn deinit(self: *App) void {
    rl.CloseWindow();
    self.allocator.destroy(self);
}

pub fn run(self: *App) void {
    if (builtin.cpu.arch.isWasm()) {
        return;
    }

    while (!rl.WindowShouldClose()) {
        self.update();
        self.draw();
    }
}

fn update(_: *App) void {}

fn draw(_: *App) void {
    rl.BeginDrawing();
    rl.ClearBackground(rl.BLACK);
    rl.DrawFPS(10, 10);
    rl.EndDrawing();
}
