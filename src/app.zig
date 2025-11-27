const std = @import("std");
const builtin = @import("builtin");

const rl = @import("core").rl;
const entt = @import("core").entt;

const circuit = @import("circuit");
const editor = @import("editor");
const gfx = @import("gfx");

const InputSystem = editor.InputSystem;
const RenderSystem = gfx.RenderSystem;
const Simulation = circuit.Simulation;
const AppState = editor.AppState;
const Gate = circuit.Gate;
const CompoundState = circuit.CompoundState;

const App = @This();

allocator: std.mem.Allocator,
window_size: rl.Vector2,
window_title: [:0]const u8,
registry: entt.Registry,
state: AppState,
simulation: Simulation,
input_system: InputSystem,
render_system: RenderSystem,

pub fn init(
    allocator: std.mem.Allocator,
    window_size: rl.Vector2,
    window_title: [:0]const u8,
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
            .selected_entities = .{},
            .dragged_wires = .{},
            .compound_gates = .{},
        },
        .simulation = Simulation.init(),
        .input_system = InputSystem.init(allocator),
        .render_system = RenderSystem.init(),
    };

    rl.InitWindow(
        @as(c_int, @intFromFloat(window_size.x)),
        @as(c_int, @intFromFloat(window_size.y)),
        window_title.ptr,
    );
    rl.SetTargetFPS(60);

    rl.SetExitKey(rl.KEY_NULL);

    return app;
}

pub fn deinit(self: *App) void {
    // Clean up Gate internal states
    var gate_view = self.registry.view(.{Gate}, .{});
    var gate_it = gate_view.entityIterator();
    while (gate_it.next()) |entity| {
        const gate = self.registry.get(Gate, entity);
        if (gate.internal_state) |ptr| {
            const state_ptr = @as(*CompoundState, @ptrCast(@alignCast(ptr)));
            circuit.factory.destroyCompoundState(self.allocator, state_ptr);
        }
    }

    self.state.selected_entities.deinit(self.allocator);
    self.state.dragged_wires.deinit(self.allocator);
    for (self.state.compound_gates.items) |*template| {
        template.gates.deinit(self.allocator);
        template.wires.deinit(self.allocator);
    }
    self.state.compound_gates.deinit(self.allocator);

    self.input_system.deinit();
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
    self.input_system.update(&self.registry, &self.state, self.window_size, self.render_system.camera);
    self.simulation.update(&self.registry, self.allocator) catch |err| {
        std.debug.print("Simulation error: {}\n", .{err});
    };
}

fn draw(self: *App) void {
    self.render_system.update(&self.registry, self.window_size, self.state);
}
