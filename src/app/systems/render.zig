const std = @import("std");
const rl = @import("raylib").rl;
const entt = @import("entt");
const components = @import("components");
const theme_mod = @import("../theme.zig");
const Theme = theme_mod.Theme;
const types = @import("../types.zig");

const Transform = components.Transform;
const Gate = components.Gate;
const Wire = components.Wire;
const Label = components.Label;

const GRID_SIZE: i32 = 20;

pub const RenderSystem = struct {
    
    pub fn init() RenderSystem {
        return .{};
    }

    pub fn update(self: *RenderSystem, registry: *entt.Registry, window_size: rl.Vector2, state: types.AppState) void {
        _ = self;
        rl.BeginDrawing();
        defer rl.EndDrawing();

        rl.ClearBackground(Theme.background);

        drawGrid(window_size);
        drawWires(registry);
        drawGates(registry, state);
        drawInteractions(registry, window_size, state);
        drawToolbar(window_size, state);

        rl.DrawFPS(10, 10);
    }
};

fn drawGrid(window_size: rl.Vector2) void {
    const width = @as(c_int, @intFromFloat(window_size.x));
    const height = @as(c_int, @intFromFloat(window_size.y));

    var x: i32 = 0;
    while (x < width) : (x += GRID_SIZE) {
        rl.DrawLine(x, 0, x, height, Theme.grid_line);
    }

    var y: i32 = 0;
    while (y < height) : (y += GRID_SIZE) {
        rl.DrawLine(0, y, width, y, Theme.grid_line);
    }
}

fn drawWires(registry: *entt.Registry) void {
    var wire_view = registry.view(.{ Wire, rl.Color }, .{});
    var wire_it = wire_view.entityIterator();
    while (wire_it.next()) |entity| {
        const wire = registry.getConst(Wire, entity);
        var color = Theme.wire_inactive;
        var thickness: f32 = 2.0;

        if (wire.active) {
            color = Theme.wire_active;
            // Glow effect
            rl.DrawLineEx(wire.start, wire.end, 4.0, rl.Fade(color, 0.4));
            thickness = 2.0;
        }
        rl.DrawLineEx(wire.start, wire.end, thickness, color);
    }
}

fn drawGates(registry: *entt.Registry, state: types.AppState) void {
    var view = registry.view(.{ Transform, Gate }, .{});
    var it = view.entityIterator();
    while (it.next()) |entity| {
        const transform = registry.getConst(Transform, entity);
        const gate = registry.getConst(Gate, entity);
        drawGateBody(gate, transform.position);

        // Draw Label
        if (registry.tryGetConst(Label, entity)) |label| {
            drawLabel(label, transform.position, gate.width, state.interaction, entity);
        }
    }
}

fn drawLabel(label: Label, pos: rl.Vector2, gate_width: f32, interaction: types.InteractionState, entity: entt.Entity) void {
    var is_editing = false;
    switch (interaction) {
        .EditingLabel => |e| if (e == entity) {
            is_editing = true;
        },
        else => {},
    }

    if (label.len > 0 or is_editing) {
        const text = if (label.len > 0) label.text[0..label.len] else "";
        const text_w = rl.MeasureText(text.ptr, 10);
        const text_pos_x = @as(c_int, @intFromFloat(pos.x + gate_width / 2.0)) - @divTrunc(text_w, 2);
        const text_pos_y = @as(c_int, @intFromFloat(pos.y - 15));

        if (is_editing) {
            // Draw editing background
            rl.DrawRectangle(text_pos_x - 2, text_pos_y - 2, text_w + 4 + 5, 14, Theme.gate_body);
            rl.DrawRectangleLines(text_pos_x - 2, text_pos_y - 2, text_w + 4 + 5, 14, Theme.wire_active);

            // Blinking cursor
            if (@mod(@as(i32, @intFromFloat(rl.GetTime() * 2.0)), 2) == 0) {
                rl.DrawLine(text_pos_x + text_w + 2, text_pos_y, text_pos_x + text_w + 2, text_pos_y + 10, Theme.wire_active);
            }
        }

        rl.DrawText(text.ptr, text_pos_x, text_pos_y, 10, Theme.gate_text);
    }
}

fn drawGateBody(gate: Gate, position: rl.Vector2) void {
    const body_rect = rl.Rectangle{
        .x = position.x + 10,
        .y = position.y + 5,
        .width = gate.width - 20,
        .height = gate.height - 10,
    };

    const out_pos = gate.getOutputPos(position);
    const in0_pos = gate.getInputPos(position, 0);
    const in1_pos = gate.getInputPos(position, 1);

    if (gate.gate_type == .INPUT or gate.gate_type == .OUTPUT) {
        const center = rl.Vector2{
            .x = body_rect.x + body_rect.width / 2.0,
            .y = body_rect.y + body_rect.height / 2.0,
        };
        const radius = @min(body_rect.width, body_rect.height) / 2.0;

        if (gate.output) {
            rl.DrawCircleV(center, radius, Theme.wire_active);
            if (gate.gate_type == .OUTPUT) {
                // Extra glow for output
                rl.DrawCircleV(center, radius + 2.0, rl.Fade(Theme.wire_active, 0.5));
            }
        } else {
            rl.DrawCircleV(center, radius, Theme.gate_body);
            rl.DrawCircleLines(@as(c_int, @intFromFloat(center.x)), @as(c_int, @intFromFloat(center.y)), radius, Theme.gate_border);
        }

        // Connections
        if (gate.gate_type == .INPUT) {
            rl.DrawLineEx(.{ .x = center.x + radius, .y = center.y }, out_pos, 2.0, Theme.gate_border);
            drawPin(out_pos, gate.output);
        } else if (gate.gate_type == .OUTPUT) {
            rl.DrawLineEx(.{ .x = center.x - radius, .y = center.y }, in0_pos, 2.0, Theme.gate_border);
            drawPin(in0_pos, gate.inputs[0]); // Input pin
        }

        return;
    }

    // Rectangular Gates (AND, OR, NOT)
    rl.DrawRectangleRec(body_rect, Theme.gate_body);
    rl.DrawRectangleLinesEx(body_rect, 2.0, Theme.gate_border);

    const stub_color = Theme.gate_border;
    rl.DrawLineEx(.{ .x = out_pos.x - 10, .y = out_pos.y }, out_pos, 2.0, stub_color);

    rl.DrawLineEx(in0_pos, .{ .x = in0_pos.x + 10, .y = in0_pos.y }, 2.0, stub_color);

    if (gate.gate_type != .NOT) {
        rl.DrawLineEx(.{ .x = in0_pos.x + 10, .y = in0_pos.y }, .{ .x = in0_pos.x + 10, .y = body_rect.y }, 2.0, stub_color);
        rl.DrawLineEx(in1_pos, .{ .x = in1_pos.x + 10, .y = in1_pos.y }, 2.0, stub_color);
        rl.DrawLineEx(.{ .x = in1_pos.x + 10, .y = in1_pos.y }, .{ .x = in1_pos.x + 10, .y = body_rect.y + body_rect.height }, 2.0, stub_color);
    }

    const type_text = switch (gate.gate_type) {
        .AND => "AND",
        .OR => "OR",
        .NOT => "NOT",
        else => "",
    };

    const text_width = rl.MeasureText(type_text, 10);
    rl.DrawText(
        type_text,
        @as(c_int, @intFromFloat(body_rect.x + body_rect.width / 2.0)) - @divTrunc(text_width, 2),
        @as(c_int, @intFromFloat(body_rect.y + body_rect.height / 2.0)) - 5,
        10,
        Theme.gate_text,
    );

    drawPin(in0_pos, gate.inputs[0]);
    if (gate.gate_type != .NOT) {
        drawPin(in1_pos, gate.inputs[1]);
    }
    drawPin(out_pos, gate.output);
}

fn drawPin(pos: rl.Vector2, active: bool) void {
    const color = if (active) Theme.wire_active else Theme.gate_border;
    if (active) {
        rl.DrawCircle(@as(c_int, @intFromFloat(pos.x)), @as(c_int, @intFromFloat(pos.y)), 4, color);
    } else {
        rl.DrawCircleLines(@as(c_int, @intFromFloat(pos.x)), @as(c_int, @intFromFloat(pos.y)), 4, color);
    }
}

fn drawInteractions(registry: *entt.Registry, window_size: rl.Vector2, state: types.AppState) void {
    switch (state.interaction) {
        .DrawingWire => |start_pos| {
            if (start_pos) |start| {
                const mouse_pos = rl.GetMousePosition();
                rl.DrawLineEx(start, mouse_pos, 2.0, rl.Fade(Theme.wire_inactive, 0.5));
            }
        },
        .PlacingGate => {
            drawPlacementPreview(registry, window_size, state);
        },
        else => {},
    }
}

fn drawPlacementPreview(registry: *entt.Registry, window_size: rl.Vector2, state: types.AppState) void {
    const mouse_pos = rl.GetMousePosition();
    const toolbar_y = window_size.y - Theme.Layout.toolbar_height;

    if (mouse_pos.y >= toolbar_y) return;

    // Check for overlaps with existing gates or pins to hide preview
    var overlap = false;
    var check_view = registry.view(.{ Transform, Gate }, .{});
    var check_it = check_view.entityIterator();
    while (check_it.next()) |entity| {
        const t = check_view.getConst(Transform, entity);
        const g = check_view.getConst(Gate, entity);

        // Gate Body
        const rect = rl.Rectangle{ .x = t.position.x, .y = t.position.y, .width = g.width, .height = g.height };
        if (rl.CheckCollisionPointRec(mouse_pos, rect)) {
            overlap = true;
            break;
        }

        // Pins (Reuse simple radius check)
        const pin_radius = 10.0;
        if (g.gate_type != .OUTPUT and rl.CheckCollisionPointCircle(mouse_pos, g.getOutputPos(t.position), pin_radius)) {
            overlap = true;
            break;
        }
        if (g.gate_type != .INPUT) {
            if (rl.CheckCollisionPointCircle(mouse_pos, g.getInputPos(t.position, 0), pin_radius)) {
                overlap = true;
                break;
            }
            if (g.gate_type != .NOT and g.gate_type != .OUTPUT and rl.CheckCollisionPointCircle(mouse_pos, g.getInputPos(t.position, 1), pin_radius)) {
                overlap = true;
                break;
            }
        }
    }

    if (!overlap) {
        var check_wire_view = registry.view(.{Wire}, .{});
        var check_wire_it = check_wire_view.entityIterator();
        while (check_wire_it.next()) |e| {
            const w = check_wire_view.getConst(e);
            if (rl.CheckCollisionPointCircle(mouse_pos, w.start, 8.0) or rl.CheckCollisionPointCircle(mouse_pos, w.end, 8.0)) {
                overlap = true;
                break;
            }
        }
    }

    if (!overlap) {
        const grid_size_f = @as(f32, @floatFromInt(GRID_SIZE));

        const temp_gate = Gate{ .gate_type = state.current_gate_type };
        const half_w = temp_gate.width / 2.0;
        const half_h = temp_gate.height / 2.0;

        const raw_tl_x = mouse_pos.x - half_w;
        const raw_tl_y = mouse_pos.y - half_h;

        const snapped_tl_x = @round(raw_tl_x / grid_size_f) * grid_size_f;
        const snapped_tl_y = @round(raw_tl_y / grid_size_f) * grid_size_f;
        const place_pos = rl.Vector2{ .x = snapped_tl_x, .y = snapped_tl_y };

        drawGateBody(temp_gate, place_pos); // Ghost
    }
}

fn drawToolbar(window_size: rl.Vector2, state: types.AppState) void {
    const toolbar_y = window_size.y - Theme.Layout.toolbar_height;
    rl.DrawRectangle(0, @as(c_int, @intFromFloat(toolbar_y)), @as(c_int, @intFromFloat(window_size.x)), @as(c_int, @intFromFloat(Theme.Layout.toolbar_height)), Theme.toolbar_bg);

    var start_x: f32 = 10.0;

    const gates = [_]components.GateType{ .AND, .OR, .NOT, .INPUT, .OUTPUT };
    for (gates) |gate_type| {
        const rect = rl.Rectangle{
            .x = start_x,
            .y = toolbar_y + Theme.Layout.button_margin_top,
            .width = Theme.Layout.button_width,
            .height = Theme.Layout.toolbar_height - (Theme.Layout.button_margin_top * 2.0),
        };

        var color = Theme.button_inactive;
        const is_selected = switch (state.interaction) {
            .PlacingGate => state.current_gate_type == gate_type,
            else => false,
        };

        if (is_selected) {
            color = Theme.button_active;
        } else {
            if (rl.CheckCollisionPointRec(rl.GetMousePosition(), rect)) {
                color = Theme.button_hover;
            }
        }

        rl.DrawRectangleRec(rect, color);
        rl.DrawRectangleLinesEx(rect, 2.0, Theme.button_border);

        const text = switch (gate_type) {
            .AND => "AND",
            .OR => "OR",
            .NOT => "NOT",
            .INPUT => "IN",
            .OUTPUT => "OUT",
        };
        const text_w = rl.MeasureText(text, 20);
        rl.DrawText(text, @as(c_int, @intFromFloat(rect.x + rect.width / 2.0)) - @divTrunc(text_w, 2), @as(c_int, @intFromFloat(rect.y + rect.height / 2.0)) - 10, 20, Theme.gate_text);

        start_x += Theme.Layout.button_width + Theme.Layout.button_padding;
    }
}
