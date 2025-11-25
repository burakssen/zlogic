const std = @import("std");
const builtin = @import("builtin");

const rl = @import("raylib").rl;
const entt = @import("entt");

const components = @import("components");
const systems = @import("systems");

const input = @import("input.zig");
const renderer = @import("renderer.zig");
const types = @import("types.zig");

const App = @This();

allocator: std.mem.Allocator,
window_size: rl.Vector2,
window_title: []const u8,
registry: entt.Registry,
state: types.AppState,
simulation: systems.Simulation,

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
        .registry = entt.Registry.init(allocator),
        .state = .{
            .interaction = .Idle,
            .current_gate_type = .AND,
        },
        .simulation = systems.Simulation.init(),
    };

    rl.InitWindow(
        @as(c_int, @intFromFloat(window_size.x)),
        @as(c_int, @intFromFloat(window_size.y)),
        window_title.ptr,
    );
    rl.SetTargetFPS(60);

    return app;
}

pub fn deinit(self: *App) void {
    self.simulation.deinit(self.allocator);
    self.registry.deinit();
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

fn update(self: *App) void {
    input.updateInput(&self.registry, &self.state, self.window_size);
    self.simulation.update(&self.registry, self.allocator) catch |err| {
        std.debug.print("Simulation error: {}\n", .{err});
    };
}

fn draw(self: *App) void {
    renderer.draw(&self.registry, self.window_size, self.state);
}
