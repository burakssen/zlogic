const std = @import("std");
const entt = @import("core").entt;
const rl = @import("core").rl;
const components = @import("components.zig");
const Transform = @import("core").Transform;

const Gate = components.Gate;
const Wire = components.Wire;
const CompoundState = components.CompoundState;

pub const Simulation = struct {
    active_points: std.ArrayListUnmanaged(rl.Vector2),

    pub fn init() Simulation {
        return .{
            .active_points = .{},
        };
    }

    pub fn deinit(self: *Simulation, allocator: std.mem.Allocator) void {
        self.active_points.deinit(allocator);
    }

    pub fn update(self: *Simulation, registry: *entt.Registry, allocator: std.mem.Allocator) std.mem.Allocator.Error!void {
        self.resetCircuit(registry);
        try self.propagateSignals(registry, allocator);
        try self.computeLogic(registry, allocator);
    }

    fn resetCircuit(self: *Simulation, registry: *entt.Registry) void {
        _ = self;
        var gate_view = registry.view(.{Gate}, .{});
        var gate_it = gate_view.entityIterator();
        while (gate_it.next()) |entity| {
            var gate = registry.get(Gate, entity);
            gate.inputs = 0;
        }

        var wire_view = registry.view(.{Wire}, .{});
        var wire_it = wire_view.entityIterator();
        while (wire_it.next()) |entity| {
            var wire = registry.get(Wire, entity);
            wire.active = false;
        }
    }

    fn propagateSignals(self: *Simulation, registry: *entt.Registry, allocator: std.mem.Allocator) std.mem.Allocator.Error!void {
        self.active_points.clearRetainingCapacity();

        // 1. Collect Active Sources (Gate Outputs that are ON)
        var source_view = registry.view(.{ Gate, Transform }, .{});
        var source_it = source_view.entityIterator();
        while (source_it.next()) |entity| {
            const gate = registry.getConst(Gate, entity);
            const transform = registry.getConst(Transform, entity);

            var i: u4 = 0;
            while (i < gate.output_count) : (i += 1) {
                if (gate.getOutput(i)) {
                    try self.active_points.append(allocator, gate.getOutputPos(transform.position, i));
                }
            }
        }

        // 2. Propagate Signal through Wires (BFS)
        var i: usize = 0;
        var wire_view = registry.view(.{Wire}, .{});

        while (i < self.active_points.items.len) : (i += 1) {
            const point = self.active_points.items[i];

            var wire_it = wire_view.entityIterator();
            while (wire_it.next()) |entity| {
                var wire = registry.get(Wire, entity);

                if (wire.active) continue;

                const connected_start = rl.CheckCollisionPointCircle(wire.start, point, 5.0);
                const connected_end = rl.CheckCollisionPointCircle(wire.end, point, 5.0);

                if (connected_start or connected_end) {
                    wire.active = true;
                    try self.active_points.append(allocator, wire.start);
                    try self.active_points.append(allocator, wire.end);
                }
            }
        }

        // 3. Apply Signals to Gate Inputs
        var target_view = registry.view(.{ Gate, Transform }, .{});
        var target_it = target_view.entityIterator();
        while (target_it.next()) |entity| {
            var gate = registry.get(Gate, entity);
            const transform = registry.getConst(Transform, entity);

            var pin_idx: u4 = 0;
            while (pin_idx < gate.input_count) : (pin_idx += 1) {
                const in_pos = gate.getInputPos(transform.position, pin_idx);

                for (self.active_points.items) |pt| {
                    if (rl.CheckCollisionPointCircle(pt, in_pos, 5.0)) {
                        gate.setInput(pin_idx, true);
                        break; 
                    }
                }
            }
        }
    }

    fn computeLogic(_: *Simulation, registry: *entt.Registry, allocator: std.mem.Allocator) std.mem.Allocator.Error!void {
        var gate_view = registry.view(.{Gate}, .{});
        var gate_it = gate_view.entityIterator();
        while (gate_it.next()) |entity| {
            var gate = registry.get(Gate, entity);
            switch (gate.gate_type) {
                .AND => gate.setOutput(0, gate.getInput(0) and gate.getInput(1)),
                .OR => gate.setOutput(0, gate.getInput(0) or gate.getInput(1)),
                .NOT => gate.setOutput(0, !gate.getInput(0)),
                .OUTPUT => gate.setOutput(0, gate.getInput(0)),
                .INPUT => {}, 
                .COMPOUND => {
                    if (gate.internal_state) |ptr| {
                        const state = @as(*CompoundState, @ptrCast(@alignCast(ptr)));

                        // Sync In
                        for (state.input_map.items, 0..) |inner_entity, idx| {
                            var inner_gate = state.registry.get(Gate, inner_entity);
                            inner_gate.setOutput(0, gate.getInput(@intCast(idx)));
                        }

                        // Step Internal Simulation
                        var inner_sim = Simulation.init();
                        defer inner_sim.deinit(allocator);
                        try inner_sim.update(state.registry, allocator);

                        // Sync Out
                        for (state.output_map.items, 0..) |inner_entity, idx| {
                            const inner_gate = state.registry.getConst(Gate, inner_entity);
                            gate.setOutput(@intCast(idx), inner_gate.getOutput(0));
                        }
                    }
                },
            }
        }
    }
};
