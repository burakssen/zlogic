const std = @import("std");
const rl = @import("core").rl;
const entt = @import("core").entt;
const circuit = @import("circuit");
const GateType = circuit.GateType;
const CompoundGateTemplate = circuit.CompoundGateTemplate;

pub const InteractionState = union(enum) {
    Idle,
    PlacingGate,
    PlacingCompoundGate: usize,
    DrawingWire: ?rl.Vector2,
    EditingLabel: entt.Entity,
    EditingTemplateName: usize,
    GateMenu: struct { entity: entt.Entity, position: rl.Vector2 },
    WireMenu: struct { entity: entt.Entity, position: rl.Vector2 },
    SelectionMenu: rl.Vector2,
    BoxSelecting: rl.Rectangle,
    MovingSelection: rl.Vector2,
};

pub const WireDragRef = struct {
    wire: entt.Entity,
    is_start: bool,
    gate: entt.Entity,
};

pub const AppState = struct {
    interaction: InteractionState,
    current_gate_type: GateType,
    selected_entities: std.ArrayListUnmanaged(entt.Entity),
    dragged_wires: std.ArrayListUnmanaged(WireDragRef),
    compound_gates: std.ArrayListUnmanaged(CompoundGateTemplate),
};
