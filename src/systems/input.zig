const std = @import("std");
const rl = @import("raylib").rl;
const entt = @import("entt");
const components = @import("components");
const types = @import("types");
const theme_mod = @import("theme");
const Theme = theme_mod.Theme;
const factory = @import("factory"); // This might be an issue if factory is not a package. 
// Checked build.zig/zon? Factory seems to be imported as module "factory" in app/input.zig
// Let's check imports in input.zig: const factory = @import("factory");
// I will assume "factory" is a module.

const Transform = components.Transform;
const Gate = components.Gate;
const Wire = components.Wire;
const GateType = components.GateType;
const Label = components.Label;

// Constants
const GRID_SIZE: i32 = 20; // duplicated from renderer. Should be shared.

const ConnectionPoint = struct {
    position: rl.Vector2,
    entity_to_split: ?entt.Entity = null,
};

pub const InputSystem = struct {
    
    pub fn init() InputSystem {
        return .{};
    }

    pub fn update(self: *InputSystem, registry: *entt.Registry, state: *types.AppState, window_size: rl.Vector2) void {
        const mouse_pos = rl.GetMousePosition();

        // 1. Handle Modal/Continuous Interactions
        if (self.handleLabelEditing(registry, state, mouse_pos)) return;
        if (self.handleGateMovement(registry, state, mouse_pos)) return;

        // 2. Handle Toolbar Interaction
        if (self.handleToolbar(state, mouse_pos, window_size)) return;

        // 3. Handle Canvas Interactions (Clicking, Placing, Wiring)
        self.handleCanvas(registry, state, mouse_pos);
        
        // 4. Handle Cancellation
        if (rl.IsMouseButtonPressed(rl.MOUSE_BUTTON_RIGHT)) {
            state.interaction = .Idle;
        }
    }

    fn handleLabelEditing(self: *InputSystem, registry: *entt.Registry, state: *types.AppState, mouse_pos: rl.Vector2) bool {
        _ = self;
        switch (state.interaction) {
            .EditingLabel => |entity| {
                if (rl.IsKeyPressed(rl.KEY_ENTER) or rl.IsKeyPressed(rl.KEY_ESCAPE) or (rl.IsMouseButtonPressed(rl.MOUSE_BUTTON_LEFT) and !isMouseOverEntity(registry, entity, mouse_pos))) {
                    state.interaction = .Idle;
                    return true;
                }

                if (registry.tryGet(Label, entity)) |label| {
                    var key = rl.GetCharPressed();
                    while (key > 0) {
                        if ((key >= 32) and (key <= 125) and (label.len < 31)) {
                            label.text[label.len] = @as(u8, @intCast(key));
                            label.len += 1;
                            label.text[label.len] = 0;
                        }
                        key = rl.GetCharPressed();
                    }

                    if (rl.IsKeyPressed(rl.KEY_BACKSPACE)) {
                        if (label.len > 0) {
                            label.len -= 1;
                            label.text[label.len] = 0;
                        }
                    }
                }
                return true; // Block other inputs
            },
            else => return false,
        }
    }

    fn handleGateMovement(self: *InputSystem, registry: *entt.Registry, state: *types.AppState, mouse_pos: rl.Vector2) bool {
        switch (state.interaction) {
            .MovingGate => |data| {
                if (!rl.IsMouseButtonDown(rl.MOUSE_BUTTON_LEFT)) {
                    // Release
                    if (registry.tryGet(Transform, data.entity)) |t| {
                        const diff = rl.Vector2Subtract(t.position, data.initial_pos);
                        if (rl.Vector2LengthSqr(diff) < 4.0) {
                             // It was a click (Toggle input)
                            if (registry.tryGet(Gate, data.entity)) |g| {
                                if (g.gate_type == .INPUT) {
                                    g.output = !g.output;
                                }
                            }
                        }
                    }
                    state.interaction = .Idle;
                } else {
                    // Drag
                    self.applyGateMove(registry, data, mouse_pos);
                }
                return true;
            },
            else => return false,
        }
    }

    fn applyGateMove(self: *InputSystem, registry: *entt.Registry, data: anytype, mouse_pos: rl.Vector2) void {
        _ = self;
        const grid_size_f = @as(f32, @floatFromInt(GRID_SIZE));
        
        if (registry.tryGet(Transform, data.entity)) |t| {
            if (registry.tryGetConst(Gate, data.entity)) |g| {
                const raw_pos = rl.Vector2Subtract(mouse_pos, data.offset);
                const new_snapped_x = @round(raw_pos.x / grid_size_f) * grid_size_f;
                const new_snapped_y = @round(raw_pos.y / grid_size_f) * grid_size_f;
                const new_pos = rl.Vector2{ .x = new_snapped_x, .y = new_snapped_y };

                const old_pos = t.position;

                if (new_pos.x != old_pos.x or new_pos.y != old_pos.y) {
                    const delta = rl.Vector2Subtract(new_pos, old_pos);
                    t.position = new_pos;

                    // Update connected wires
                    updateConnectedWires(registry, g, old_pos, delta);
                }
            }
        }
    }

    fn handleToolbar(self: *InputSystem, state: *types.AppState, mouse_pos: rl.Vector2, window_size: rl.Vector2) bool {
        _ = self;
        const toolbar_y = window_size.y - Theme.Layout.toolbar_height;

        if (mouse_pos.y >= toolbar_y) {
            if (rl.IsMouseButtonPressed(rl.MOUSE_BUTTON_LEFT)) {
                var start_x: f32 = 10.0;
                const gates = [_]GateType{ .AND, .OR, .NOT, .INPUT, .OUTPUT };
                
                for (gates) |gate_type| {
                    const rect = rl.Rectangle{
                        .x = start_x,
                        .y = toolbar_y + Theme.Layout.button_margin_top,
                        .width = Theme.Layout.button_width,
                        .height = Theme.Layout.toolbar_height - (Theme.Layout.button_margin_top * 2.0),
                    };
                    if (rl.CheckCollisionPointRec(mouse_pos, rect)) {
                        state.current_gate_type = gate_type;
                        state.interaction = .PlacingGate;
                    }
                    start_x += Theme.Layout.button_width + Theme.Layout.button_padding;
                }
            }
            return true; // Consumed input in toolbar area
        }
        return false;
    }

    fn handleCanvas(self: *InputSystem, registry: *entt.Registry, state: *types.AppState, mouse_pos: rl.Vector2) void {
        if (!rl.IsMouseButtonPressed(rl.MOUSE_BUTTON_LEFT)) return;

        const grid_size_f = @as(f32, @floatFromInt(GRID_SIZE));
        const snapped_x = @round(mouse_pos.x / grid_size_f) * grid_size_f;
        const snapped_y = @round(mouse_pos.y / grid_size_f) * grid_size_f;
        const snapped_pos = rl.Vector2{ .x = snapped_x, .y = snapped_y };

        // 1. Check Label Editing (Alt + Click)
        if (rl.IsKeyDown(rl.KEY_LEFT_ALT) or rl.IsKeyDown(rl.KEY_RIGHT_ALT)) {
            if (self.tryStartLabelEdit(registry, state, mouse_pos)) return;
        }

        // 2. Check Connection Points / Wires
        const match = getHoveredConnectionPoint(registry, mouse_pos);

        // Split wire if clicked on segment
        if (match) |m| {
            if (m.entity_to_split) |e| {
                factory.splitWire(registry, e, m.position);
            }
        }

        switch (state.interaction) {
            .DrawingWire => |start_opt| {
                const end = if (match) |m| m.position else snapped_pos;
                if (start_opt) |start| {
                    factory.createWire(registry, start, end);
                }
                state.interaction = .Idle;
            },
            .PlacingGate => {
                if (match) |m| {
                    // If clicked on a point while placing gate, switch to wire mode? 
                    // Original logic did this.
                    state.interaction = .{ .DrawingWire = m.position };
                } else {
                    self.placeGate(registry, state, mouse_pos);
                }
            },
            .Idle => {
                if (match) |m| {
                    state.interaction = .{ .DrawingWire = m.position };
                } else {
                    // Check for Gate Dragging
                    if (getHoveredGate(registry, mouse_pos)) |entity| {
                        if (registry.tryGetConst(Transform, entity)) |t| {
                            const offset = rl.Vector2Subtract(mouse_pos, t.position);
                            state.interaction = .{ .MovingGate = .{ .entity = entity, .offset = offset, .initial_pos = t.position } };
                        }
                    }
                }
            },
            else => {},
        }
    }

    fn tryStartLabelEdit(self: *InputSystem, registry: *entt.Registry, state: *types.AppState, mouse_pos: rl.Vector2) bool {
        _ = self;
        var view = registry.view(.{ Transform, Gate }, .{});
        var it = view.entityIterator();
        while (it.next()) |entity| {
            const t = view.getConst(Transform, entity);
            const g = view.getConst(Gate, entity);
            const rect = rl.Rectangle{ .x = t.position.x, .y = t.position.y, .width = g.width, .height = g.height };
            if (rl.CheckCollisionPointRec(mouse_pos, rect)) {
                state.interaction = .{ .EditingLabel = entity };
                return true;
            }
        }
        return false;
    }

    fn placeGate(self: *InputSystem, registry: *entt.Registry, state: *types.AppState, mouse_pos: rl.Vector2) void {
        _ = self;
        const grid_size_f = @as(f32, @floatFromInt(GRID_SIZE));
        const temp_gate = Gate{ .gate_type = state.current_gate_type };
        const half_w = temp_gate.width / 2.0;
        const half_h = temp_gate.height / 2.0;

        const raw_tl_x = mouse_pos.x - half_w;
        const raw_tl_y = mouse_pos.y - half_h;

        const snapped_tl_x = @round(raw_tl_x / grid_size_f) * grid_size_f;
        const snapped_tl_y = @round(raw_tl_y / grid_size_f) * grid_size_f;
        const place_pos = rl.Vector2{ .x = snapped_tl_x, .y = snapped_tl_y };

        factory.createGate(registry, state.current_gate_type, place_pos);
    }
};

// Helper Functions (Private)

fn updateConnectedWires(registry: *entt.Registry, g: Gate, old_pos: rl.Vector2, delta: rl.Vector2) void {
    var wire_view = registry.view(.{Wire}, .{});
    var wire_it = wire_view.entityIterator();
    while (wire_it.next()) |w_entity| {
        var wire = wire_view.get(w_entity);

        const movePointIfMatch = struct {
            fn do(pt: *rl.Vector2, target: rl.Vector2, d: rl.Vector2) void {
                if (rl.CheckCollisionPointCircle(target, pt.*, 1.0)) {
                    pt.* = rl.Vector2Add(pt.*, d);
                }
            }
        }.do;

        if (g.gate_type != .OUTPUT) {
            movePointIfMatch(&wire.start, g.getOutputPos(old_pos), delta);
            movePointIfMatch(&wire.end, g.getOutputPos(old_pos), delta);
        }

        if (g.gate_type != .INPUT) {
            movePointIfMatch(&wire.start, g.getInputPos(old_pos, 0), delta);
            movePointIfMatch(&wire.end, g.getInputPos(old_pos, 0), delta);

            if (g.gate_type != .NOT and g.gate_type != .OUTPUT) {
                movePointIfMatch(&wire.start, g.getInputPos(old_pos, 1), delta);
                movePointIfMatch(&wire.end, g.getInputPos(old_pos, 1), delta);
            }
        }
    }
}

fn getHoveredConnectionPoint(registry: *entt.Registry, mouse_pos: rl.Vector2) ?ConnectionPoint {
    const pin_radius = 8.0;

    // 1. Check Gate Pins
    var gate_view = registry.view(.{ Transform, Gate }, .{});
    var gate_it = gate_view.entityIterator();
    while (gate_it.next()) |entity| {
        const t = gate_view.getConst(Transform, entity);
        const g = gate_view.getConst(Gate, entity);

        if (g.gate_type != .OUTPUT) {
            const out_pos = g.getOutputPos(t.position);
            if (rl.CheckCollisionPointCircle(mouse_pos, out_pos, pin_radius)) {
                return .{ .position = out_pos };
            }
        }

        if (g.gate_type != .INPUT) {
            const in0 = g.getInputPos(t.position, 0);
            if (rl.CheckCollisionPointCircle(mouse_pos, in0, pin_radius)) {
                return .{ .position = in0 };
            }

            if (g.gate_type != .NOT and g.gate_type != .OUTPUT) {
                const in1 = g.getInputPos(t.position, 1);
                if (rl.CheckCollisionPointCircle(mouse_pos, in1, pin_radius)) {
                    return .{ .position = in1 };
                }
            }
        }
    }

    // 2. Check Wire Endpoints & Segments
    var wire_view = registry.view(.{Wire}, .{});
    var wire_it = wire_view.entityIterator();
    while (wire_it.next()) |entity| {
        const wire = wire_view.getConst(entity);

        if (rl.CheckCollisionPointCircle(mouse_pos, wire.start, pin_radius)) {
            return .{ .position = wire.start };
        }
        if (rl.CheckCollisionPointCircle(mouse_pos, wire.end, pin_radius)) {
            return .{ .position = wire.end };
        }

        const ab = rl.Vector2Subtract(wire.end, wire.start);
        const ap = rl.Vector2Subtract(mouse_pos, wire.start);
        const len_sqr = rl.Vector2LengthSqr(ab);

        if (len_sqr > 0.0) {
            const t = rl.Vector2DotProduct(ap, ab) / len_sqr;
            const t_clamped = @max(0.0, @min(1.0, t));
            const closest = rl.Vector2Add(wire.start, rl.Vector2Scale(ab, t_clamped));

            if (rl.CheckCollisionPointCircle(mouse_pos, closest, pin_radius)) {
                return .{ .position = closest, .entity_to_split = entity };
            }
        }
    }
    return null;
}

fn getHoveredGate(registry: *entt.Registry, mouse_pos: rl.Vector2) ?entt.Entity {
    var view = registry.view(.{ Transform, Gate }, .{});
    var it = view.entityIterator();
    while (it.next()) |entity| {
        const t = view.getConst(Transform, entity);
        const g = view.getConst(Gate, entity);
        const rect = rl.Rectangle{ .x = t.position.x, .y = t.position.y, .width = g.width, .height = g.height };
        if (rl.CheckCollisionPointRec(mouse_pos, rect)) {
            return entity;
        }
    }
    return null;
}

fn isMouseOverEntity(registry: *entt.Registry, entity: entt.Entity, mouse_pos: rl.Vector2) bool {
    if (!registry.valid(entity)) return false;
    if (registry.tryGetConst(Transform, entity)) |t| {
        if (registry.tryGetConst(Gate, entity)) |g| {
            const rect = rl.Rectangle{ .x = t.position.x, .y = t.position.y, .width = g.width, .height = g.height };
            return rl.CheckCollisionPointRec(mouse_pos, rect);
        }
    }
    return false;
}
