const std = @import("std");
const rl = @import("raylib").rl;
const entt = @import("entt");
const components = @import("components");

const Transform = components.Transform;
const Gate = components.Gate;
const Wire = components.Wire;
const GateType = components.GateType;
const Label = components.Label;

pub fn createWire(registry: *entt.Registry, start: rl.Vector2, end: rl.Vector2) void {
    const entity = registry.create();
    registry.add(entity, Wire{ .start = start, .end = end });
    registry.add(entity, rl.WHITE); 
}

pub fn createGate(registry: *entt.Registry, gate_type: GateType, position: rl.Vector2) void {
    const entity = registry.create();
    registry.add(entity, Transform{
        .position = position,
        .rotation = 0.0,
        .scale = .{ .x = 1.0, .y = 1.0 },
    });
    registry.add(entity, Gate{ .gate_type = gate_type });
    registry.add(entity, Label{});
    registry.add(entity, rl.GREEN);
}

pub fn splitWire(registry: *entt.Registry, entity: entt.Entity, split_point: rl.Vector2) void {
    const wire = registry.get(Wire, entity);
    const start = wire.start;
    const end = wire.end;

    createWire(registry, start, split_point);
    createWire(registry, split_point, end);
    
    registry.destroy(entity);
}
