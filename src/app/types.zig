const rl = @import("raylib").rl;
const entt = @import("entt");
const components = @import("components");

pub const InteractionState = union(enum) {
    Idle,
    PlacingGate,
    DrawingWire: ?rl.Vector2,
    EditingLabel: entt.Entity,
    MovingGate: struct { entity: entt.Entity, offset: rl.Vector2, initial_pos: rl.Vector2 },
};

pub const AppState = struct {
    interaction: InteractionState,
    current_gate_type: components.GateType,
};