const std = @import("std");
const rl = @import("core").rl;
const entt = @import("core").entt;
const circuit = @import("circuit");
const editor_state = @import("editor").state;
const core = @import("core");

const Theme = core.Theme;

const Transform = @import("core").Transform;
const Gate = circuit.Gate;
const Wire = circuit.Wire;
const Label = circuit.Label;
const GateType = circuit.GateType;

const AppState = editor_state.AppState;
const InteractionState = editor_state.InteractionState;

const GRID_SIZE = Theme.grid_size;

pub const RenderSystem = struct {
    camera: rl.Camera2D,

    pub fn init() RenderSystem {
        return .{
            .camera = .{
                .offset = .{ .x = 0, .y = 0 },
                .target = .{ .x = 0, .y = 0 },
                .rotation = 0,
                .zoom = 1.0,
            },
        };
    }

    pub fn update(self: *RenderSystem, registry: *entt.Registry, window_size: rl.Vector2, state: AppState) void {
        // Handle Zoom/Pan Input directly here or in InputSystem? 
        // Usually InputSystem. But for simplicity, let's do basic camera control here or let InputSystem do it.
        // If I put it here, I don't need to change AppState right now.
        // But "InputSystem" is for "Logic" input. Camera control is often considered part of Input/Window handling.
        // Let's check mouse wheel here for zoom.
        
        const wheel = rl.GetMouseWheelMove();
        if (wheel != 0) {
            const mouseWorldPos = rl.GetScreenToWorld2D(rl.GetMousePosition(), self.camera);
            self.camera.offset = rl.GetMousePosition();
            self.camera.target = mouseWorldPos;
            const scale_factor = 1.0 + (0.25 * @abs(wheel));
            if (wheel < 0) {
                self.camera.zoom = @max(0.125, self.camera.zoom / scale_factor);
            } else {
                self.camera.zoom = @min(64.0, self.camera.zoom * scale_factor);
            }
        }
        
        if (rl.IsMouseButtonDown(rl.MOUSE_BUTTON_RIGHT)) {
            const delta = rl.GetMouseDelta();
            const delta_v = rl.Vector2Scale(delta, -1.0 / self.camera.zoom);
            self.camera.target = rl.Vector2Add(self.camera.target, delta_v);
        }

        rl.BeginDrawing();
        defer rl.EndDrawing();

        rl.ClearBackground(Theme.background);

        rl.BeginMode2D(self.camera);
            // Draw world content
            // Grid needs to be huge or dynamic. 
            // For now, let's draw a larger grid centered around target?
            // Or just draw fixed grid but it won't cover everything if panned.
            // Let's try drawing grid based on camera view?
            drawGrid(window_size, self.camera);
            drawWires(registry);
            drawGates(registry, state);
            drawSelectionHighlights(registry, state);
            drawSelectionBox(state);
            drawWorldInteractions(registry, window_size, state, self.camera);
        rl.EndMode2D();

        // UI
        drawUIInteractions(registry, window_size, state);
        drawToolbar(window_size, state);

        rl.DrawFPS(10, 10);
    }
};

fn getNormalizedRect(rect: rl.Rectangle) rl.Rectangle {
    var r = rect;
    if (r.width < 0) {
        r.x += r.width;
        r.width *= -1;
    }
    if (r.height < 0) {
        r.y += r.height;
        r.height *= -1;
    }
    return r;
}

fn drawSelectionBox(state: AppState) void {
    switch (state.interaction) {
        .BoxSelecting => |rect| {
            const norm_rect = getNormalizedRect(rect);
            rl.DrawRectangleLinesEx(norm_rect, 1.0, Theme.wire_active);
            rl.DrawRectangleRec(norm_rect, rl.Fade(Theme.wire_active, 0.1));
        },
        else => {},
    }
}

fn drawSelectionHighlights(registry: *entt.Registry, state: AppState) void {
    if (state.selected_entities.items.len == 0) return;

    var min_x: f32 = std.math.inf(f32);
    var min_y: f32 = std.math.inf(f32);
    var max_x: f32 = -std.math.inf(f32);
    var max_y: f32 = -std.math.inf(f32);

    for (state.selected_entities.items) |entity| {
        if (registry.tryGetConst(Transform, entity)) |t| {
            if (registry.tryGetConst(Gate, entity)) |g| {
                const rect = g.getRect(t.position);
                min_x = @min(min_x, rect.x);
                min_y = @min(min_y, rect.y);
                max_x = @max(max_x, rect.x + rect.width);
                max_y = @max(max_y, rect.y + rect.height);
            }
        }
        
        if (registry.tryGetConst(Wire, entity)) |w| {
            min_x = @min(min_x, @min(w.start.x, w.end.x));
            min_y = @min(min_y, @min(w.start.y, w.end.y));
            max_x = @max(max_x, @max(w.start.x, w.end.x));
            max_y = @max(max_y, @max(w.start.y, w.end.y));
        }
    }

    if (min_x != std.math.inf(f32)) {
        const padding = 4.0;
        const rect = rl.Rectangle{
            .x = min_x - padding,
            .y = min_y - padding,
            .width = (max_x - min_x) + padding * 2.0,
            .height = (max_y - min_y) + padding * 2.0
        };
        rl.DrawRectangleRoundedLines(rect, 0.1, 8, Theme.wire_active);
    }
}

fn drawGrid(window_size: rl.Vector2, camera: rl.Camera2D) void {
    // Calculate visible world area
    const screen_w = window_size.x;
    const screen_h = window_size.y;
    
    const top_left = rl.GetScreenToWorld2D(.{ .x = 0, .y = 0 }, camera);
    const bottom_right = rl.GetScreenToWorld2D(.{ .x = screen_w, .y = screen_h }, camera);
    
    const start_x = @floor(top_left.x / @as(f32, @floatFromInt(GRID_SIZE))) * @as(f32, @floatFromInt(GRID_SIZE));
    const end_x = bottom_right.x;
    const start_y = @floor(top_left.y / @as(f32, @floatFromInt(GRID_SIZE))) * @as(f32, @floatFromInt(GRID_SIZE));
    const end_y = bottom_right.y;

    var x = start_x;
    while (x < end_x) : (x += @as(f32, @floatFromInt(GRID_SIZE))) {
        rl.DrawLineV(.{ .x = x, .y = top_left.y }, .{ .x = x, .y = bottom_right.y }, Theme.grid_line);
    }

    var y = start_y;
    while (y < end_y) : (y += @as(f32, @floatFromInt(GRID_SIZE))) {
        rl.DrawLineV(.{ .x = top_left.x, .y = y }, .{ .x = bottom_right.x, .y = y }, Theme.grid_line);
    }
}

fn drawWires(registry: *entt.Registry) void {
    var wire_view = registry.view(.{Wire}, .{});
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

fn drawGates(registry: *entt.Registry, state: AppState) void {
    var view = registry.view(.{ Transform, Gate }, .{});
    var it = view.entityIterator();
    while (it.next()) |entity| {
        const transform = registry.getConst(Transform, entity);
        const gate = registry.getConst(Gate, entity);
        drawGateBody(gate, transform.position, state);

        // Draw Label
        if (registry.tryGetConst(Label, entity)) |label| {
            drawLabel(label, transform.position, gate.width, state.interaction, entity);
        }
    }
}

fn drawLabel(label: Label, pos: rl.Vector2, gate_width: f32, interaction: InteractionState, entity: entt.Entity) void {
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

fn drawGateBody(gate: Gate, position: rl.Vector2, state: AppState) void {
    const body_rect = rl.Rectangle{
        .x = position.x + 5,
        .y = position.y + 5,
        .width = gate.width - 10,
        .height = gate.height - 10,
    };

    // Draw Pins and Stubs
    // Outputs
    if (gate.gate_type != .OUTPUT) {
        var i: u8 = 0;
        while (i < gate.output_count) : (i += 1) {
             const out_pos = gate.getOutputPos(position, i);
             if (gate.gate_type == .INPUT) {
                 // Input gate body is circle, special case handled below?
             } else {
                const stub_start = rl.Vector2{ .x = out_pos.x - 5, .y = out_pos.y };
                rl.DrawLineEx(stub_start, out_pos, 2.0, Theme.gate_border);
             }
             drawPin(out_pos, gate.getOutput(@intCast(i)));
        }
    }

    // Inputs
    if (gate.gate_type != .INPUT) {
        var i: u8 = 0;
        while (i < gate.input_count) : (i += 1) {
            const in_pos = gate.getInputPos(position, i);
            if (gate.gate_type == .OUTPUT) {
                // Output gate special case
            } else {
                const stub_end = rl.Vector2{ .x = in_pos.x + 5, .y = in_pos.y };
                rl.DrawLineEx(in_pos, stub_end, 2.0, Theme.gate_border);
            }
            drawPin(in_pos, gate.getInput(@intCast(i)));
        }
    }

    // Body Shapes
    if (gate.gate_type == .INPUT or gate.gate_type == .OUTPUT) {
        const center = rl.Vector2{
            .x = body_rect.x + body_rect.width / 2.0,
            .y = body_rect.y + body_rect.height / 2.0,
        };
        const radius = @min(body_rect.width, body_rect.height) / 2.0;

        if (gate.gate_type == .INPUT) {
             // Input Gate: output is what matters
             if (gate.getOutput(0)) {
                rl.DrawCircleV(center, radius, Theme.wire_active);
             } else {
                rl.DrawCircleV(center, radius, Theme.gate_body);
                rl.DrawCircleLines(@as(c_int, @intFromFloat(center.x)), @as(c_int, @intFromFloat(center.y)), radius, Theme.gate_border);
             }
             // Connection drawn above in loop
        } else {
             // Output Gate: input is what matters
             if (gate.getInput(0)) {
                rl.DrawCircleV(center, radius, Theme.wire_active);
                rl.DrawCircleV(center, radius + 2.0, rl.Fade(Theme.wire_active, 0.5));
             } else {
                rl.DrawCircleV(center, radius, Theme.gate_body);
                rl.DrawCircleLines(@as(c_int, @intFromFloat(center.x)), @as(c_int, @intFromFloat(center.y)), radius, Theme.gate_border);
             }
             // Connection drawn above
        }
        return;
    }

    // Rectangular Gates (AND, OR, NOT, COMPOUND)
    if (gate.gate_type == .COMPOUND) {
        // IC Look
        rl.DrawRectangleRec(body_rect, Theme.gate_body);
        rl.DrawRectangleLinesEx(body_rect, 2.0, Theme.gate_border);

        // Pin 1 Indicator (Dot on top-left)
        const dot_radius = 2.5;
        const dot_pos = rl.Vector2{ 
            .x = body_rect.x + 8.0, 
            .y = body_rect.y + 8.0 
        };
        rl.DrawCircleV(dot_pos, dot_radius, Theme.gate_border);

        // Notch on the left edge
        const notch_radius = 6.0;
        const notch_center = rl.Vector2{ 
            .x = body_rect.x, 
            .y = body_rect.y + body_rect.height / 2.0 
        };
        // Draw notch as a filled circle with background color, then border arc?
        // Simplest effective look: Darker semi-circle stroke or just indentation.
        // Let's draw a filled circle (Theme.background) to "cut" the body, then outline it.
        rl.DrawCircleV(notch_center, notch_radius, Theme.background);
        rl.DrawRing(notch_center, notch_radius, notch_radius + 1.5, -90.0, 90.0, 16, Theme.gate_border);

    } else {
        rl.DrawRectangleRounded(body_rect, 0.3, 8, Theme.gate_body);
        rl.DrawRectangleRoundedLines(body_rect, 0.3, 8, Theme.gate_border);
    }

    var type_text: []const u8 = "";
    switch (gate.gate_type) {
        .AND => type_text = "AND",
        .OR => type_text = "OR",
        .NOT => type_text = "NOT",
        .COMPOUND => {
            type_text = "IC";
            if (gate.template_id) |tid| {
                if (tid < state.compound_gates.items.len) {
                    const template = state.compound_gates.items[tid];
                    type_text = template.name[0..template.name_len];
                }
            }
        },
        else => {},
    }

    const text_width = rl.MeasureText(type_text.ptr, 10);
    rl.DrawText(
        type_text.ptr,
        @as(c_int, @intFromFloat(body_rect.x + body_rect.width / 2.0)) - @divTrunc(text_width, 2),
        @as(c_int, @intFromFloat(body_rect.y + body_rect.height / 2.0)) - 5,
        10,
        Theme.gate_text,
    );
}

fn drawPin(pos: rl.Vector2, active: bool) void {
    const color = if (active) Theme.wire_active else Theme.gate_border;
    if (active) {
        rl.DrawCircle(@as(c_int, @intFromFloat(pos.x)), @as(c_int, @intFromFloat(pos.y)), 4, color);
    } else {
        rl.DrawCircleLines(@as(c_int, @intFromFloat(pos.x)), @as(c_int, @intFromFloat(pos.y)), 4, color);
    }
}

fn drawWorldInteractions(registry: *entt.Registry, window_size: rl.Vector2, state: AppState, camera: rl.Camera2D) void {
    const mouse_world_pos = rl.GetScreenToWorld2D(rl.GetMousePosition(), camera);

    switch (state.interaction) {
        .DrawingWire => |start_pos| {
            if (start_pos) |start| {
                rl.DrawLineEx(start, mouse_world_pos, 2.0, rl.Fade(Theme.wire_inactive, 0.5));
            }
        },
        .PlacingGate => {
            drawPlacementPreview(registry, window_size, state, mouse_world_pos);
        },
        .PlacingCompoundGate => {
            drawPlacementPreview(registry, window_size, state, mouse_world_pos);
        },
        else => {},
    }
}

fn drawUIInteractions(registry: *entt.Registry, window_size: rl.Vector2, state: AppState) void {
    _ = registry;
    _ = window_size;
    switch (state.interaction) {
        .GateMenu => |data| {
            drawGateMenu(data.position);
        },
        .WireMenu => |data| {
            drawWireMenu(data.position);
        },
        .SelectionMenu => |pos| {
            drawSelectionMenu(pos);
        },
        else => {},
    }
}

fn drawSelectionMenu(pos: rl.Vector2) void {
    const menu_w = Theme.Layout.menu_width;
    const item_h = Theme.Layout.menu_item_height;
    const menu_h = item_h * 2.0;

    // Shadow
    const shadow_offset = 4.0;
    const shadow_rect = rl.Rectangle{
        .x = pos.x + shadow_offset,
        .y = pos.y + shadow_offset,
        .width = menu_w,
        .height = menu_h,
    };
    rl.DrawRectangleRounded(shadow_rect, 0.1, 6, rl.Fade(rl.BLACK, 0.3));

    const rect = rl.Rectangle{ .x = pos.x, .y = pos.y, .width = menu_w, .height = menu_h };

    // Background
    rl.DrawRectangleRounded(rect, 0.1, 6, Theme.gate_body);

    // Rename Item
    const rename_rect = rl.Rectangle{ .x = pos.x, .y = pos.y, .width = menu_w, .height = item_h };
    if (rl.CheckCollisionPointRec(rl.GetMousePosition(), rename_rect)) {
        const hover_rect = rl.Rectangle{
            .x = rename_rect.x + 4,
            .y = rename_rect.y + 2,
            .width = rename_rect.width - 8,
            .height = rename_rect.height - 4,
        };
        rl.DrawRectangleRounded(hover_rect, 0.2, 4, Theme.button_hover);
    }

    const text_h = 10; // Font size
    const text_y_offset = (item_h - @as(f32, @floatFromInt(text_h))) / 2.0;

    rl.DrawText("Rename", @as(c_int, @intFromFloat(pos.x + 14)), @as(c_int, @intFromFloat(pos.y + text_y_offset)), text_h, Theme.gate_text);

    // Delete Item
    const delete_rect = rl.Rectangle{ .x = pos.x, .y = pos.y + item_h, .width = menu_w, .height = item_h };
    if (rl.CheckCollisionPointRec(rl.GetMousePosition(), delete_rect)) {
        const hover_rect = rl.Rectangle{
            .x = delete_rect.x + 4,
            .y = delete_rect.y + 2,
            .width = delete_rect.width - 8,
            .height = delete_rect.height - 4,
        };
        rl.DrawRectangleRounded(hover_rect, 0.2, 4, Theme.button_hover);
    }
    rl.DrawText("Delete", @as(c_int, @intFromFloat(pos.x + 14)), @as(c_int, @intFromFloat(pos.y + item_h + text_y_offset)), text_h, Theme.gate_text);

    // Border
    rl.DrawRectangleRoundedLines(rect, 0.1, 6, Theme.wire_active);
}

fn drawWireMenu(pos: rl.Vector2) void {
    const menu_w = Theme.Layout.menu_width;
    const item_h = Theme.Layout.menu_item_height;
    const menu_h = item_h; // Only Delete

    // Shadow
    const shadow_offset = 4.0;
    const shadow_rect = rl.Rectangle{
        .x = pos.x + shadow_offset,
        .y = pos.y + shadow_offset,
        .width = menu_w,
        .height = menu_h,
    };
    rl.DrawRectangleRounded(shadow_rect, 0.1, 6, rl.Fade(rl.BLACK, 0.3));

    const rect = rl.Rectangle{ .x = pos.x, .y = pos.y, .width = menu_w, .height = menu_h };

    // Background
    rl.DrawRectangleRounded(rect, 0.1, 6, Theme.gate_body);

    // Delete Item
    const delete_rect = rl.Rectangle{ .x = pos.x, .y = pos.y, .width = menu_w, .height = item_h };
    if (rl.CheckCollisionPointRec(rl.GetMousePosition(), delete_rect)) {
        const hover_rect = rl.Rectangle{
            .x = delete_rect.x + 4,
            .y = delete_rect.y + 2,
            .width = delete_rect.width - 8,
            .height = delete_rect.height - 4,
        };
        rl.DrawRectangleRounded(hover_rect, 0.2, 4, Theme.button_hover);
    }

    const text_h = 10;
    const text_y_offset = (item_h - @as(f32, @floatFromInt(text_h))) / 2.0;
    rl.DrawText("Delete", @as(c_int, @intFromFloat(pos.x + 14)), @as(c_int, @intFromFloat(pos.y + text_y_offset)), text_h, Theme.gate_text);

    // Border
    rl.DrawRectangleRoundedLines(rect, 0.1, 6, Theme.wire_active);
}

fn drawGateMenu(pos: rl.Vector2) void {
    const menu_w = Theme.Layout.menu_width;
    const item_h = Theme.Layout.menu_item_height;
    const menu_h = item_h * 2.0;

    // Shadow
    const shadow_offset = 4.0;
    const shadow_rect = rl.Rectangle{
        .x = pos.x + shadow_offset,
        .y = pos.y + shadow_offset,
        .width = menu_w,
        .height = menu_h,
    };
    rl.DrawRectangleRounded(shadow_rect, 0.1, 6, rl.Fade(rl.BLACK, 0.3));

    const rect = rl.Rectangle{ .x = pos.x, .y = pos.y, .width = menu_w, .height = menu_h };

    // Background
    rl.DrawRectangleRounded(rect, 0.1, 6, Theme.gate_body);

    // Rename Item
    const rename_rect = rl.Rectangle{ .x = pos.x, .y = pos.y, .width = menu_w, .height = item_h };
    if (rl.CheckCollisionPointRec(rl.GetMousePosition(), rename_rect)) {
        const hover_rect = rl.Rectangle{
            .x = rename_rect.x + 4,
            .y = rename_rect.y + 2,
            .width = rename_rect.width - 8,
            .height = rename_rect.height - 4,
        };
        rl.DrawRectangleRounded(hover_rect, 0.2, 4, Theme.button_hover);
    }

    const text_h = 10; // Font size
    const text_y_offset = (item_h - @as(f32, @floatFromInt(text_h))) / 2.0;

    rl.DrawText("Rename", @as(c_int, @intFromFloat(pos.x + 14)), @as(c_int, @intFromFloat(pos.y + text_y_offset)), text_h, Theme.gate_text);

    // Delete Item
    const delete_rect = rl.Rectangle{ .x = pos.x, .y = pos.y + item_h, .width = menu_w, .height = item_h };
    if (rl.CheckCollisionPointRec(rl.GetMousePosition(), delete_rect)) {
        const hover_rect = rl.Rectangle{
            .x = delete_rect.x + 4,
            .y = delete_rect.y + 2,
            .width = delete_rect.width - 8,
            .height = delete_rect.height - 4,
        };
        rl.DrawRectangleRounded(hover_rect, 0.2, 4, Theme.button_hover);
    }
    rl.DrawText("Delete", @as(c_int, @intFromFloat(pos.x + 14)), @as(c_int, @intFromFloat(pos.y + item_h + text_y_offset)), text_h, Theme.gate_text);

    // Border
    rl.DrawRectangleRoundedLines(rect, 0.1, 6, Theme.wire_active);
}

fn drawPlacementPreview(registry: *entt.Registry, window_size: rl.Vector2, state: AppState, mouse_world_pos: rl.Vector2) void {
    const mouse_screen_pos = rl.GetMousePosition();
    const toolbar_y = window_size.y - Theme.Layout.toolbar_height;

    if (mouse_screen_pos.y >= toolbar_y) return;

    // Check for overlaps with existing gates or pins to hide preview
    var overlap = false;
    var check_view = registry.view(.{ Transform, Gate }, .{});
    var check_it = check_view.entityIterator();
    while (check_it.next()) |entity| {
        const t = check_view.getConst(Transform, entity);
        const g = check_view.getConst(Gate, entity);

        // Gate Body
        if (rl.CheckCollisionPointRec(mouse_world_pos, g.getRect(t.position))) {
            overlap = true;
            break;
        }

        // Pins (Reuse simple radius check)
        const pin_radius = 10.0;
        if (g.gate_type != .OUTPUT) {
            var i: u8 = 0;
            while (i < g.output_count) : (i += 1) {
                if (rl.CheckCollisionPointCircle(mouse_world_pos, g.getOutputPos(t.position, i), pin_radius)) {
                    overlap = true;
                    break;
                }
            }
        }
        if (g.gate_type != .INPUT) {
            var i: u8 = 0;
            while (i < g.input_count) : (i += 1) {
                if (rl.CheckCollisionPointCircle(mouse_world_pos, g.getInputPos(t.position, i), pin_radius)) {
                    overlap = true;
                    break;
                }
            }
        }
    }

    if (!overlap) {
        var check_wire_view = registry.view(.{Wire}, .{});
        var check_wire_it = check_wire_view.entityIterator();
        while (check_wire_it.next()) |e| {
            const w = check_wire_view.getConst(e);
            if (rl.CheckCollisionPointCircle(mouse_world_pos, w.start, 8.0) or rl.CheckCollisionPointCircle(mouse_world_pos, w.end, 8.0)) {
                overlap = true;
                break;
            }
        }
    }

    if (!overlap) {
        const grid_size_f = @as(f32, @floatFromInt(GRID_SIZE));

        // TODO: If placing compound gate, we need to know its size/pins from template to draw ghost correctly
        // For now using default Gate defaults which might be wrong for Compound
        var temp_gate = Gate.init(state.current_gate_type);
        
        switch (state.interaction) {
            .PlacingCompoundGate => |idx| {
                temp_gate.gate_type = .COMPOUND;
                // Ideally we fetch template and set counts/size here
                // But for ghost, defaults are okay-ish or we can try to look it up
                if (idx < state.compound_gates.items.len) {
                    const template = state.compound_gates.items[idx];
                    // Calculate counts
                    var input_count: u8 = 0;
                    var output_count: u8 = 0;
                    for (template.gates.items) |g| {
                        if (g.type == .INPUT) input_count += 1;
                        if (g.type == .OUTPUT) output_count += 1;
                    }
                    temp_gate.input_count = input_count;
                    temp_gate.output_count = output_count;
                    
                    const max_pins = @max(input_count, output_count);
                    if (max_pins > 2) {
                        temp_gate.height = @as(f32, @floatFromInt(max_pins)) * 20.0;
                    }
                }
            },
            else => {},
        }

        const half_w = temp_gate.width / 2.0;
        const half_h = temp_gate.height / 2.0;

        const raw_tl_x = mouse_world_pos.x - half_w;
        const raw_tl_y = mouse_world_pos.y - half_h;

        const snapped_tl_x = @round(raw_tl_x / grid_size_f) * grid_size_f;
        const snapped_tl_y = @round(raw_tl_y / grid_size_f) * grid_size_f;
        const place_pos = rl.Vector2{ .x = snapped_tl_x, .y = snapped_tl_y };

        drawGateBody(temp_gate, place_pos, state); // Ghost
    }
}

fn drawToolbar(window_size: rl.Vector2, state: AppState) void {
    const toolbar_y = window_size.y - Theme.Layout.toolbar_height;
    rl.DrawRectangle(0, @as(c_int, @intFromFloat(toolbar_y)), @as(c_int, @intFromFloat(window_size.x)), @as(c_int, @intFromFloat(Theme.Layout.toolbar_height)), Theme.toolbar_bg);

    var start_x: f32 = 10.0;

    // 1. Standard Gates
    for (GateType.ALL) |gate_type| {
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
            .COMPOUND => unreachable,
        };
        const text_w = rl.MeasureText(text, 20);
        rl.DrawText(text, @as(c_int, @intFromFloat(rect.x + rect.width / 2.0)) - @divTrunc(text_w, 2), @as(c_int, @intFromFloat(rect.y + rect.height / 2.0)) - 10, 20, Theme.gate_text);

        start_x += Theme.Layout.button_width + Theme.Layout.button_padding;
    }

    // 2. Separator
    start_x += 20.0;

    // 3. Create Compound Gate Button (+)
    const plus_rect = rl.Rectangle{
        .x = start_x,
        .y = toolbar_y + Theme.Layout.button_margin_top,
        .width = Theme.Layout.button_width,
        .height = Theme.Layout.toolbar_height - (Theme.Layout.button_margin_top * 2.0),
    };

    var plus_color = Theme.button_inactive;
    if (rl.CheckCollisionPointRec(rl.GetMousePosition(), plus_rect)) {
        plus_color = Theme.button_hover;
    }
    // Visual feedback if clicked is handled by InputSystem, but here we can just show hover.

    rl.DrawRectangleRec(plus_rect, plus_color);
    rl.DrawRectangleLinesEx(plus_rect, 2.0, Theme.button_border);

    const plus_text = "+";
    const plus_w = rl.MeasureText(plus_text, 30);
    rl.DrawText(plus_text, @as(c_int, @intFromFloat(plus_rect.x + plus_rect.width / 2.0)) - @divTrunc(plus_w, 2), @as(c_int, @intFromFloat(plus_rect.y + plus_rect.height / 2.0)) - 15, 30, Theme.gate_text);

    start_x += Theme.Layout.button_width + Theme.Layout.button_padding + 20.0;

    // 4. Compound Gates List
    for (state.compound_gates.items, 0..) |template, i| {
        const rect = rl.Rectangle{
            .x = start_x,
            .y = toolbar_y + Theme.Layout.button_margin_top,
            .width = Theme.Layout.button_width * 1.5, // Wider for names
            .height = Theme.Layout.toolbar_height - (Theme.Layout.button_margin_top * 2.0),
        };

        var is_editing = false;
        switch (state.interaction) {
            .EditingTemplateName => |idx| if (idx == i) { is_editing = true; },
            else => {},
        }

        // Check if this template is currently being placed (need logic for this later)
        // For now just standard button
        var color = Theme.button_inactive;
        if (rl.CheckCollisionPointRec(rl.GetMousePosition(), rect) or is_editing) {
            color = Theme.button_hover;
        }

        rl.DrawRectangleRec(rect, color);
        if (is_editing) {
            rl.DrawRectangleLinesEx(rect, 2.0, Theme.wire_active);
        } else {
            rl.DrawRectangleLinesEx(rect, 2.0, Theme.button_border);
        }

        // Truncate name if needed or just draw
        rl.DrawText(&template.name, @as(c_int, @intFromFloat(rect.x + 5)), @as(c_int, @intFromFloat(rect.y + rect.height / 2.0)) - 5, 10, Theme.gate_text);

        if (is_editing) {
            const text_w = rl.MeasureText(&template.name, 10);
            if (@mod(@as(i32, @intFromFloat(rl.GetTime() * 2.0)), 2) == 0) {
                const cx = @as(c_int, @intFromFloat(rect.x + 5)) + text_w + 2;
                const cy = @as(c_int, @intFromFloat(rect.y + rect.height / 2.0)) - 5;
                rl.DrawLine(cx, cy, cx, cy + 10, Theme.wire_active);
            }
        }

        start_x += (Theme.Layout.button_width * 1.5) + Theme.Layout.button_padding;
    }
}
