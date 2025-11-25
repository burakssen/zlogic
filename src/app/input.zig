const std = @import("std");
const rl = @import("raylib").rl;
const entt = @import("entt");
const components = @import("components");
const types = @import("types.zig");
const renderer = @import("renderer.zig");
const Theme = @import("theme.zig").Theme;
const factory = @import("factory");

const Transform = components.Transform;
const Gate = components.Gate;
const Wire = components.Wire;
const GateType = components.GateType;
const Label = components.Label;

const ConnectionPoint = struct {
    position: rl.Vector2,
    entity_to_split: ?entt.Entity = null,
};

pub fn updateInput(registry: *entt.Registry, state: *types.AppState, window_size: rl.Vector2) void {
    const mouse_pos = rl.GetMousePosition();

    // Handle Label Editing
    switch (state.interaction) {
        .EditingLabel => |entity| {
            if (rl.IsKeyPressed(rl.KEY_ENTER) or rl.IsKeyPressed(rl.KEY_ESCAPE) or (rl.IsMouseButtonPressed(rl.MOUSE_BUTTON_LEFT) and !isMouseOverEntity(registry, entity, mouse_pos))) {
                state.interaction = .Idle;
                return;
            }
            
            if (registry.tryGet(Label, entity)) |label| {
                var key = rl.GetCharPressed();
                while (key > 0) {
                    if ((key >= 32) and (key <= 125) and (label.len < 31)) {
                        label.text[label.len] = @as(u8, @intCast(key));
                        label.len += 1;
                        label.text[label.len] = 0; // Null terminate
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
            return; // Block other inputs while editing
        },
        else => {},
    }

    const grid_size_f = @as(f32, @floatFromInt(renderer.GRID_SIZE));
    const snapped_x = @round(mouse_pos.x / grid_size_f) * grid_size_f;
    const snapped_y = @round(mouse_pos.y / grid_size_f) * grid_size_f;
    const snapped_pos = rl.Vector2{ .x = snapped_x, .y = snapped_y };

    const toolbar_y = window_size.y - Theme.Layout.toolbar_height;

    if (mouse_pos.y >= toolbar_y) {
        if (rl.IsMouseButtonPressed(rl.MOUSE_BUTTON_LEFT)) {
            var start_x: f32 = 10.0;

            const gates = [_]GateType{ .AND, .OR, .NOT, .SWITCH, .OUTPUT };
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
        return; 
    }

    if (rl.IsMouseButtonPressed(rl.MOUSE_BUTTON_LEFT)) {
        // Label Editing (Alt + Click)
        if (rl.IsKeyDown(rl.KEY_LEFT_ALT) or rl.IsKeyDown(rl.KEY_RIGHT_ALT)) {
             var view = registry.view(.{Transform, Gate}, .{});
             var it = view.entityIterator();
             while (it.next()) |entity| {
                 const t = view.getConst(Transform, entity);
                 const g = view.getConst(Gate, entity);
                 const rect = rl.Rectangle{
                    .x = t.position.x, 
                    .y = t.position.y, 
                    .width = g.width, 
                    .height = g.height 
                 };
                 if (rl.CheckCollisionPointRec(mouse_pos, rect)) {
                     state.interaction = .{ .EditingLabel = entity };
                     return;
                 }
             }
        }

        if (handleSwitchToggle(registry, mouse_pos)) {
            return;
        }

        const match = getHoveredConnectionPoint(registry, mouse_pos);
        
        // If we hit a wire segment, split it immediately to create a valid node
        if (match) |m| {
            if (m.entity_to_split) |e| {
                factory.splitWire(registry, e, m.position);
            }
        }

        switch (state.interaction) {
            .DrawingWire => |start_opt| {
                // Use the matched position (pin, endpoint, or new split node) or snap
                const end = if (match) |m| m.position else snapped_pos;
                
                if (start_opt) |start| {
                     factory.createWire(registry, start, end);
                }
                state.interaction = .Idle; 
            },
            .PlacingGate => {
                if (match) |m| {
                    state.interaction = .{ .DrawingWire = m.position };
                } else {
                    // Place Gate
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
            },
            .Idle => {
                if (match) |m| {
                    state.interaction = .{ .DrawingWire = m.position };
                } else {
                    // Check for Gate Dragging
                    if (getHoveredGate(registry, mouse_pos)) |entity| {
                        if (registry.tryGetConst(Transform, entity)) |t| {
                             const offset = vSub(mouse_pos, t.position);
                             state.interaction = .{ .MovingGate = .{ .entity = entity, .offset = offset } };
                        }
                    }
                }
            },
            .EditingLabel => {}, // Handled at start of function
            .MovingGate => |data| {
                if (rl.IsMouseButtonReleased(rl.MOUSE_BUTTON_LEFT)) {
                    state.interaction = .Idle;
                } else {
                    if (registry.tryGet(Transform, data.entity)) |t| {
                        if (registry.tryGetConst(Gate, data.entity)) |g| {
                            const raw_pos = vSub(mouse_pos, data.offset);
                            const new_snapped_x = @round(raw_pos.x / grid_size_f) * grid_size_f;
                            const new_snapped_y = @round(raw_pos.y / grid_size_f) * grid_size_f;
                            const new_pos = rl.Vector2{ .x = new_snapped_x, .y = new_snapped_y };
                            
                            const old_pos = t.position;

                            if (new_pos.x != old_pos.x or new_pos.y != old_pos.y) {
                                const delta = vSub(new_pos, old_pos);
                                t.position = new_pos;

                                // Move connected wires
                                var wire_view = registry.view(.{Wire}, .{});
                                var wire_it = wire_view.entityIterator();
                                while (wire_it.next()) |w_entity| {
                                    var wire = wire_view.get(w_entity);
                                    
                                    // Helper to check and move pin connection
                                    const movePointIfMatch = struct {
                                        fn do(pt: *rl.Vector2, target: rl.Vector2, d: rl.Vector2) void {
                                            if (rl.CheckCollisionPointCircle(target, pt.*, 1.0)) {
                                                pt.* = vAdd(pt.*, d);
                                            }
                                        }
                                    }.do;

                                    // Check Output Pin
                                    if (g.gate_type != .OUTPUT) { // Output gate has no output pin
                                        movePointIfMatch(&wire.start, g.getOutputPos(old_pos), delta);
                                        movePointIfMatch(&wire.end, g.getOutputPos(old_pos), delta);
                                    }
                                    
                                    // Check Input Pins
                                    if (g.gate_type != .SWITCH) {
                                         movePointIfMatch(&wire.start, g.getInputPos(old_pos, 0), delta);
                                         movePointIfMatch(&wire.end, g.getInputPos(old_pos, 0), delta);

                                         if (g.gate_type != .NOT and g.gate_type != .OUTPUT) {
                                             movePointIfMatch(&wire.start, g.getInputPos(old_pos, 1), delta);
                                             movePointIfMatch(&wire.end, g.getInputPos(old_pos, 1), delta);
                                         }
                                    }
                                }
                            }
                        }
                    }
                }
            },
        }
    }

    if (rl.IsMouseButtonPressed(rl.MOUSE_BUTTON_RIGHT)) {
        state.interaction = .Idle;
    }
}

fn getHoveredConnectionPoint(registry: *entt.Registry, mouse_pos: rl.Vector2) ?ConnectionPoint {
    const pin_radius = 8.0;

    // 1. Check Gate Pins
    var gate_view = registry.view(.{Transform, Gate}, .{});
    var gate_it = gate_view.entityIterator();
    while (gate_it.next()) |entity| {
        const t = gate_view.getConst(Transform, entity);
        const g = gate_view.getConst(Gate, entity);
        
        // Output Pin (Switch, AND, OR, NOT)
        if (g.gate_type != .OUTPUT) {
            const out_pos = g.getOutputPos(t.position);
            if (rl.CheckCollisionPointCircle(mouse_pos, out_pos, pin_radius)) {
                return .{ .position = out_pos };
            }
        }
        
        // Input Pins (AND, OR, NOT, OUTPUT)
        if (g.gate_type != .SWITCH) {
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

        // Endpoints (High Priority)
        if (rl.CheckCollisionPointCircle(mouse_pos, wire.start, pin_radius)) {
            return .{ .position = wire.start };
        }
        if (rl.CheckCollisionPointCircle(mouse_pos, wire.end, pin_radius)) {
            return .{ .position = wire.end };
        }

        // Segment (Lower Priority)
        // Project mouse_pos onto segment AB
        const ab = vSub(wire.end, wire.start);
        const ap = vSub(mouse_pos, wire.start);
        const len_sqr = vLenSqr(ab);
        
        if (len_sqr > 0.0) {
            const t = vDot(ap, ab) / len_sqr;
            const t_clamped = @max(0.0, @min(1.0, t));
            
            const closest = vAdd(wire.start, vScale(ab, t_clamped));
            
            if (rl.CheckCollisionPointCircle(mouse_pos, closest, pin_radius)) {
                 return .{ 
                     .position = closest, 
                     .entity_to_split = entity 
                 };
            }
        }
    }

    return null;
}

fn handleSwitchToggle(registry: *entt.Registry, mouse_pos: rl.Vector2) bool {
    var view = registry.view(.{ Transform, Gate }, .{});
    var it = view.entityIterator();
    while (it.next()) |entity| {
        const t = view.getConst(Transform, entity);
        var g = view.get(Gate, entity);
        if (g.gate_type == .SWITCH) {
            const rect = rl.Rectangle{
                .x = t.position.x,
                .y = t.position.y,
                .width = g.width,
                .height = g.height,
            };
            if (rl.CheckCollisionPointRec(mouse_pos, rect)) {
                g.output = !g.output;
                return true;
            }
        }
    }
    return false;
}

fn getHoveredGate(registry: *entt.Registry, mouse_pos: rl.Vector2) ?entt.Entity {
    var view = registry.view(.{Transform, Gate}, .{});
    var it = view.entityIterator();
    while (it.next()) |entity| {
        const t = view.getConst(Transform, entity);
        const g = view.getConst(Gate, entity);
        const rect = rl.Rectangle{
            .x = t.position.x, 
            .y = t.position.y, 
            .width = g.width, 
            .height = g.height 
        };
        if (rl.CheckCollisionPointRec(mouse_pos, rect)) {
            return entity;
        }
    }
    return null;
}

// Helpers
fn isMouseOverEntity(registry: *entt.Registry, entity: entt.Entity, mouse_pos: rl.Vector2) bool {
    if (!registry.valid(entity)) return false;
    if (registry.tryGetConst(Transform, entity)) |t| {
        if (registry.tryGetConst(Gate, entity)) |g| {
             const rect = rl.Rectangle{
                .x = t.position.x, 
                .y = t.position.y, 
                .width = g.width, 
                .height = g.height 
             };
             return rl.CheckCollisionPointRec(mouse_pos, rect);
        }
    }
    return false;
}

fn vSub(a: rl.Vector2, b: rl.Vector2) rl.Vector2 { return .{ .x = a.x - b.x, .y = a.y - b.y }; }
fn vAdd(a: rl.Vector2, b: rl.Vector2) rl.Vector2 { return .{ .x = a.x + b.x, .y = a.y + b.y }; }
fn vScale(a: rl.Vector2, s: f32) rl.Vector2 { return .{ .x = a.x * s, .y = a.y * s }; }
fn vDot(a: rl.Vector2, b: rl.Vector2) f32 { return a.x * b.x + a.y * b.y; }
fn vLenSqr(a: rl.Vector2) f32 { return a.x * a.x + a.y * a.y; }