const std = @import("std");
const entt = @import("entt");
const rl = @import("raylib").rl;
const components = @import("components");
const Transform = components.Transform;
const Gate = components.Gate;
const Wire = components.Wire;

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

    pub fn update(self: *Simulation, registry: *entt.Registry, allocator: std.mem.Allocator) !void {
        self.resetCircuit(registry);
        try self.propagateSignals(registry, allocator);
        self.computeLogic(registry);
    }

    fn resetCircuit(self: *Simulation, registry: *entt.Registry) void {
        _ = self;
        var gate_view = registry.view(.{Gate}, .{});
        var gate_it = gate_view.entityIterator();
        while (gate_it.next()) |entity| {
            var gate = registry.get(Gate, entity);
            gate.inputs[0] = false;
            gate.inputs[1] = false;
        }

        var wire_view = registry.view(.{Wire}, .{});
        var wire_it = wire_view.entityIterator();
        while (wire_it.next()) |entity| {
            var wire = registry.get(Wire, entity);
            wire.active = false;
        }
    }

    fn propagateSignals(self: *Simulation, registry: *entt.Registry, allocator: std.mem.Allocator) !void {
        self.active_points.clearRetainingCapacity();

        // 1. Collect Active Sources (Gate Outputs that are ON)
        var source_view = registry.view(.{ Gate, Transform }, .{});
        var source_it = source_view.entityIterator();
        while (source_it.next()) |entity| {
            const gate = registry.getConst(Gate, entity);
            const transform = registry.getConst(Transform, entity);
            if (gate.output) {
                try self.active_points.append(allocator, gate.getOutputPos(transform.position));
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

            const in0 = gate.getInputPos(transform.position, 0);
            const in1 = gate.getInputPos(transform.position, 1);

            for (self.active_points.items) |pt| {
                if (!gate.inputs[0] and rl.CheckCollisionPointCircle(pt, in0, 5.0)) {
                    gate.inputs[0] = true;
                }
                if (!gate.inputs[1] and rl.CheckCollisionPointCircle(pt, in1, 5.0)) {
                    gate.inputs[1] = true;
                }

                if (gate.inputs[0] and gate.inputs[1]) break;
            }
        }
    }

    fn computeLogic(self: *Simulation, registry: *entt.Registry) void {
        _ = self;
        var gate_view = registry.view(.{Gate}, .{});
        var gate_it = gate_view.entityIterator();
        while (gate_it.next()) |entity| {
            var gate = registry.get(Gate, entity);
            switch (gate.gate_type) {
                .AND => gate.output = gate.inputs[0] and gate.inputs[1],
                .OR => gate.output = gate.inputs[0] or gate.inputs[1],
                .NOT => gate.output = !gate.inputs[0],
                .OUTPUT => gate.output = gate.inputs[0],
                .INPUT => {}, // State handled by Input system
            }
        }
    }
};
