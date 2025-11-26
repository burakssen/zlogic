const std = @import("std");
const core = @import("core");
const rl = core.rl;
const entt = core.entt;
const Theme = core.Theme;

const circuit = @import("circuit");
const editor_state = @import("state.zig");

const factory = circuit.factory;

const Transform = core.Transform;
const Gate = circuit.Gate;
const Wire = circuit.Wire;
const GateType = circuit.GateType;
const Label = circuit.Label;
const CompoundState = circuit.CompoundState;
const CompoundGateTemplate = circuit.CompoundGateTemplate;

const AppState = editor_state.AppState;

// Constants
const GRID_SIZE = Theme.grid_size;

const ConnectionPoint = struct {
    position: rl.Vector2,
    entity_to_split: ?entt.Entity = null,
};

pub const InputSystem = struct {
    allocator: std.mem.Allocator,
    initial_entity_positions: std.AutoHashMap(entt.Entity, rl.Vector2),

    pub fn init(allocator: std.mem.Allocator) InputSystem {
        return .{
            .allocator = allocator,
            .initial_entity_positions = std.AutoHashMap(entt.Entity, rl.Vector2).init(allocator),
        };
    }

    pub fn deinit(self: *InputSystem) void {
        self.initial_entity_positions.deinit();
    }

    pub fn update(self: *InputSystem, registry: *entt.Registry, state: *AppState, window_size: rl.Vector2) void {
        const mouse_pos = rl.GetMousePosition();

        // 1. Handle Modal/Continuous Interactions
        if (self.handleLabelEditing(registry, state, mouse_pos)) return;
        if (self.handleTemplateRenaming(state)) return;
        if (self.handleGateMenu(registry, state, mouse_pos)) return;
        if (self.handleWireMenu(registry, state, mouse_pos)) return;
        if (self.handleSelectionMenu(registry, state, mouse_pos)) return;
        if (self.handleSelectionMovement(registry, state, mouse_pos)) return;
        if (self.handleBoxSelection(registry, state, mouse_pos)) return;

        // 2. Handle Toolbar Interaction
        if (self.handleToolbar(registry, state, mouse_pos, window_size)) return;

        // 3. Handle Canvas Interactions (Clicking, Placing, Wiring)
        self.handleCanvas(registry, state, mouse_pos);

        // 4. Handle Cancellation / Context Menu
        if (rl.IsMouseButtonPressed(rl.MOUSE_BUTTON_RIGHT)) {
            if (state.interaction == .Idle) {
                if (getHoveredGate(registry, mouse_pos)) |entity| {
                    var is_selected = false;
                    for (state.selected_entities.items) |e| {
                        if (e == entity) {
                            is_selected = true;
                            break;
                        }
                    }

                    if (is_selected) {
                        state.interaction = .{ .SelectionMenu = mouse_pos };
                    } else {
                        state.selected_entities.clearRetainingCapacity();
                        state.interaction = .{ .GateMenu = .{ .entity = entity, .position = mouse_pos } };
                    }
                } else if (getHoveredWire(registry, mouse_pos)) |entity| {
                    var is_selected = false;
                    for (state.selected_entities.items) |e| {
                        if (e == entity) {
                            is_selected = true;
                            break;
                        }
                    }

                    if (is_selected) {
                        state.interaction = .{ .SelectionMenu = mouse_pos };
                    } else {
                        state.selected_entities.clearRetainingCapacity();
                        state.interaction = .{ .WireMenu = .{ .entity = entity, .position = mouse_pos } };
                    }
                } else {
                    state.selected_entities.clearRetainingCapacity();
                }
            } else {
                state.interaction = .Idle;
            }
        }
    }

    fn handleSelectionMenu(self: *InputSystem, registry: *entt.Registry, state: *AppState, mouse_pos: rl.Vector2) bool {
        switch (state.interaction) {
            .SelectionMenu => |pos| {
                if (rl.IsMouseButtonPressed(rl.MOUSE_BUTTON_LEFT)) {
                    const menu_x = pos.x;
                    const menu_y = pos.y;
                    const menu_w = Theme.Layout.menu_width;
                    const item_h = Theme.Layout.menu_item_height;

                    // Rename
                    const rename_rect = rl.Rectangle{ .x = menu_x, .y = menu_y, .width = menu_w, .height = item_h };
                    if (rl.CheckCollisionPointRec(mouse_pos, rename_rect)) {
                        // Rename first item if applicable
                        if (state.selected_entities.items.len > 0) {
                            state.interaction = .{ .EditingLabel = state.selected_entities.items[0] };
                        } else {
                            state.interaction = .Idle;
                        }
                        return true;
                    }

                    // Delete
                    const delete_rect = rl.Rectangle{ .x = menu_x, .y = menu_y + item_h, .width = menu_w, .height = item_h };
                    if (rl.CheckCollisionPointRec(mouse_pos, delete_rect)) {
                        for (state.selected_entities.items) |e| {
                            if (registry.valid(e)) {
                                self.destroyEntity(registry, e);
                            }
                        }
                        state.selected_entities.clearRetainingCapacity();
                        state.interaction = .Idle;
                        return true;
                    }

                    state.interaction = .Idle;
                }
                return true;
            },
            else => return false,
        }
    }

    fn handleBoxSelection(self: *InputSystem, registry: *entt.Registry, state: *AppState, mouse_pos: rl.Vector2) bool {
        switch (state.interaction) {
            .BoxSelecting => |rect| {
                var new_rect = rect;
                new_rect.width = mouse_pos.x - rect.x;
                new_rect.height = mouse_pos.y - rect.y;

                state.interaction = .{ .BoxSelecting = new_rect };

                if (!rl.IsMouseButtonDown(rl.MOUSE_BUTTON_LEFT)) {
                    // Release
                    const normalized_rect = normalizeRect(new_rect);

                    if (!rl.IsKeyDown(rl.KEY_LEFT_SHIFT)) {
                        state.selected_entities.clearRetainingCapacity();
                    }

                    // Select Gates
                    var gate_view = registry.view(.{ Transform, Gate }, .{});
                    var gate_it = gate_view.entityIterator();
                    while (gate_it.next()) |entity| {
                        const t = gate_view.getConst(Transform, entity);
                        const g = gate_view.getConst(Gate, entity);
                        const gate_rect = g.getRect(t.position);
                        const center = rl.Vector2{ .x = gate_rect.x + gate_rect.width / 2.0, .y = gate_rect.y + gate_rect.height / 2.0 };

                        if (rl.CheckCollisionPointRec(center, normalized_rect)) {
                            self.selectEntity(state, entity);
                        }
                    }

                    // Select Wires
                    var wire_view = registry.view(.{Wire}, .{});
                    var wire_it = wire_view.entityIterator();
                    while (wire_it.next()) |entity| {
                        const w = wire_view.getConst(entity);
                        const mid = rl.Vector2Scale(rl.Vector2Add(w.start, w.end), 0.5);
                        if (rl.CheckCollisionPointRec(mid, normalized_rect)) {
                            self.selectEntity(state, entity);
                        }
                    }

                    state.interaction = .Idle;
                }
                return true;
            },
            else => return false,
        }
    }

    fn selectEntity(self: *InputSystem, state: *AppState, entity: entt.Entity) void {
        var already_selected = false;
        for (state.selected_entities.items) |e| {
            if (e == entity) {
                already_selected = true;
                break;
            }
        }
        if (!already_selected) {
            state.selected_entities.append(self.allocator, entity) catch {};
        }
    }

    fn normalizeRect(rect: rl.Rectangle) rl.Rectangle {
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

    fn handleGateMenu(self: *InputSystem, registry: *entt.Registry, state: *AppState, mouse_pos: rl.Vector2) bool {
        switch (state.interaction) {
            .GateMenu => |data| {
                if (rl.IsMouseButtonPressed(rl.MOUSE_BUTTON_LEFT)) {
                    const menu_x = data.position.x;
                    const menu_y = data.position.y;
                    const menu_w = Theme.Layout.menu_width;
                    const item_h = Theme.Layout.menu_item_height;

                    const rename_rect = rl.Rectangle{ .x = menu_x, .y = menu_y, .width = menu_w, .height = item_h };
                    if (rl.CheckCollisionPointRec(mouse_pos, rename_rect)) {
                        state.interaction = .{ .EditingLabel = data.entity };
                        return true;
                    }

                    const delete_rect = rl.Rectangle{ .x = menu_x, .y = menu_y + item_h, .width = menu_w, .height = item_h };
                    if (rl.CheckCollisionPointRec(mouse_pos, delete_rect)) {
                        self.destroyEntity(registry, data.entity);
                        state.interaction = .Idle;
                        return true;
                    }

                    state.interaction = .Idle;
                }
                return true;
            },
            else => return false,
        }
    }

    fn handleWireMenu(self: *InputSystem, registry: *entt.Registry, state: *AppState, mouse_pos: rl.Vector2) bool {
        switch (state.interaction) {
            .WireMenu => |data| {
                if (rl.IsMouseButtonPressed(rl.MOUSE_BUTTON_LEFT)) {
                    const menu_x = data.position.x;
                    const menu_y = data.position.y;
                    const menu_w = Theme.Layout.menu_width;
                    const item_h = Theme.Layout.menu_item_height;

                    const delete_rect = rl.Rectangle{ .x = menu_x, .y = menu_y, .width = menu_w, .height = item_h };
                    if (rl.CheckCollisionPointRec(mouse_pos, delete_rect)) {
                        self.destroyEntity(registry, data.entity);
                        state.interaction = .Idle;
                        return true;
                    }

                    state.interaction = .Idle;
                }
                return true;
            },
            else => return false,
        }
    }

    fn handleTemplateRenaming(self: *InputSystem, state: *AppState) bool {
        _ = self;
        switch (state.interaction) {
            .EditingTemplateName => |index| {
                if (index >= state.compound_gates.items.len) {
                    state.interaction = .Idle;
                    return true;
                }

                if (rl.IsKeyPressed(rl.KEY_ENTER) or rl.IsKeyPressed(rl.KEY_ESCAPE) or rl.IsMouseButtonPressed(rl.MOUSE_BUTTON_LEFT)) {
                    state.interaction = .Idle;
                    return true;
                }

                var template = &state.compound_gates.items[index];
                var key = rl.GetCharPressed();
                while (key > 0) {
                    if ((key >= 32) and (key <= 125) and (template.name_len < 31)) {
                        template.name[template.name_len] = @as(u8, @intCast(key));
                        template.name_len += 1;
                        template.name[template.name_len] = 0;
                    }
                    key = rl.GetCharPressed();
                }

                if (rl.IsKeyPressed(rl.KEY_BACKSPACE)) {
                    if (template.name_len > 0) {
                        template.name_len -= 1;
                        template.name[template.name_len] = 0;
                    }
                }
                return true;
            },
            else => return false,
        }
    }

    fn handleLabelEditing(self: *InputSystem, registry: *entt.Registry, state: *AppState, mouse_pos: rl.Vector2) bool {
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
                return true;
            },
            else => return false,
        }
    }

    fn handleSelectionMovement(self: *InputSystem, registry: *entt.Registry, state: *AppState, mouse_pos: rl.Vector2) bool {
        switch (state.interaction) {
            .MovingSelection => |start_pos| {
                if (!rl.IsMouseButtonDown(rl.MOUSE_BUTTON_LEFT)) {
                    // Release
                    const dist = rl.Vector2Distance(start_pos, mouse_pos);
                    if (dist < 4.0) {
                        // Clicked without moving much
                        if (state.selected_entities.items.len == 1) {
                            const entity = state.selected_entities.items[0];
                            if (registry.tryGet(Gate, entity)) |g| {
                                if (g.gate_type == .INPUT) {
                                    g.setOutput(0, !g.getOutput(0));
                                }
                            }
                        }
                    }
                    state.interaction = .Idle;
                } else {
                    // Drag
                    self.applySelectionMove(registry, state, start_pos, mouse_pos);
                }
                return true;
            },
            else => return false,
        }
    }

    fn applySelectionMove(self: *InputSystem, registry: *entt.Registry, state: *AppState, start_pos: rl.Vector2, mouse_pos: rl.Vector2) void {
        const grid_size_f = @as(f32, @floatFromInt(GRID_SIZE));
        const total_delta = rl.Vector2Subtract(mouse_pos, start_pos);

        for (state.selected_entities.items) |entity| {
            if (self.initial_entity_positions.get(entity)) |initial_pos| {
                if (registry.tryGet(Transform, entity)) |t| {
                    const target_raw = rl.Vector2Add(initial_pos, total_delta);
                    const snapped_x = @round(target_raw.x / grid_size_f) * grid_size_f;
                    const snapped_y = @round(target_raw.y / grid_size_f) * grid_size_f;
                    const new_pos = rl.Vector2{ .x = snapped_x, .y = snapped_y };

                    const old_pos = t.position;

                    if (new_pos.x != old_pos.x or new_pos.y != old_pos.y) {
                        const delta = rl.Vector2Subtract(new_pos, old_pos);
                        t.position = new_pos;

                        if (registry.tryGetConst(Gate, entity)) |g| {
                            updateConnectedWires(registry, g, old_pos, delta);
                        }
                    }
                }
            }
        }
    }

    fn handleToolbar(self: *InputSystem, registry: *entt.Registry, state: *AppState, mouse_pos: rl.Vector2, window_size: rl.Vector2) bool {
        const toolbar_y = window_size.y - Theme.Layout.toolbar_height;

        if (mouse_pos.y >= toolbar_y) {
            var start_x: f32 = 10.0;

            // 1. Standard Gates
            for (GateType.ALL) |gate_type| {
                const rect = rl.Rectangle{
                    .x = start_x,
                    .y = toolbar_y + Theme.Layout.button_margin_top,
                    .width = Theme.Layout.button_width,
                    .height = Theme.Layout.toolbar_height - (Theme.Layout.button_margin_top * 2.0),
                };
                if (rl.CheckCollisionPointRec(mouse_pos, rect)) {
                    if (rl.IsMouseButtonPressed(rl.MOUSE_BUTTON_LEFT)) {
                        state.current_gate_type = gate_type;
                        state.interaction = .PlacingGate;
                        state.selected_entities.clearRetainingCapacity();
                    }
                }
                start_x += Theme.Layout.button_width + Theme.Layout.button_padding;
            }

            start_x += 20.0;

            // 2. Create Compound Gate Button (+)
            const plus_rect = rl.Rectangle{
                .x = start_x,
                .y = toolbar_y + Theme.Layout.button_margin_top,
                .width = Theme.Layout.button_width,
                .height = Theme.Layout.toolbar_height - (Theme.Layout.button_margin_top * 2.0),
            };

            if (rl.CheckCollisionPointRec(mouse_pos, plus_rect)) {
                if (rl.IsMouseButtonPressed(rl.MOUSE_BUTTON_LEFT)) {
                    self.createCompoundGateFromSelection(registry, state);
                }
            }

            start_x += Theme.Layout.button_width + Theme.Layout.button_padding + 20.0;

            // 3. Compound Gates
            for (state.compound_gates.items, 0..) |_, i| {
                const rect = rl.Rectangle{
                    .x = start_x,
                    .y = toolbar_y + Theme.Layout.button_margin_top,
                    .width = Theme.Layout.button_width * 1.5,
                    .height = Theme.Layout.toolbar_height - (Theme.Layout.button_margin_top * 2.0),
                };
                if (rl.CheckCollisionPointRec(mouse_pos, rect)) {
                    if (rl.IsMouseButtonPressed(rl.MOUSE_BUTTON_LEFT)) {
                        state.interaction = .{ .PlacingCompoundGate = i };
                        state.selected_entities.clearRetainingCapacity();
                    } else if (rl.IsMouseButtonPressed(rl.MOUSE_BUTTON_RIGHT)) {
                        state.interaction = .{ .EditingTemplateName = i };
                    }
                }
                start_x += (Theme.Layout.button_width * 1.5) + Theme.Layout.button_padding;
            }
            return true;
        }
        return false;
    }

    fn createCompoundGateFromSelection(self: *InputSystem, registry: *entt.Registry, state: *AppState) void {
        if (state.selected_entities.items.len == 0) return;

        var min_x: f32 = 1000000.0;
        var min_y: f32 = 1000000.0;
        var has_items = false;

        for (state.selected_entities.items) |entity| {
            if (registry.tryGetConst(Transform, entity)) |t| {
                min_x = @min(min_x, t.position.x);
                min_y = @min(min_y, t.position.y);
                has_items = true;
            } else if (registry.tryGetConst(Wire, entity)) |w| {
                min_x = @min(min_x, @min(w.start.x, w.end.x));
                min_y = @min(min_y, @min(w.start.y, w.end.y));
                has_items = true;
            }
        }

        if (!has_items) return;

        const origin = rl.Vector2{ .x = min_x, .y = min_y };

        var template = CompoundGateTemplate{
            .name = [_]u8{0} ** 32,
            .name_len = 0,
            .gates = .empty,
            .wires = .empty,
        };

        for (state.selected_entities.items) |entity| {
            if (registry.tryGetConst(Gate, entity)) |g| {
                if (registry.tryGetConst(Transform, entity)) |t| {
                    const offset = rl.Vector2Subtract(t.position, origin);
                    template.gates.append(self.allocator, .{ .type = g.gate_type, .offset = offset, .template_id = g.template_id }) catch {};
                }
            } else if (registry.tryGetConst(Wire, entity)) |w| {
                const start_offset = rl.Vector2Subtract(w.start, origin);
                const end_offset = rl.Vector2Subtract(w.end, origin);
                template.wires.append(self.allocator, .{ .start_offset = start_offset, .end_offset = end_offset }) catch {};
            }
        }

        // Generate a name (e.g. "Gate 1")
        const count = state.compound_gates.items.len + 1;
        const printed = std.fmt.bufPrint(&template.name, "Gate {d}", .{count}) catch "Gate";
        template.name_len = @intCast(printed.len);

        state.compound_gates.append(self.allocator, template) catch {};
        state.selected_entities.clearRetainingCapacity();
    }

    fn handleCanvas(self: *InputSystem, registry: *entt.Registry, state: *AppState, mouse_pos: rl.Vector2) void {
        if (!rl.IsMouseButtonPressed(rl.MOUSE_BUTTON_LEFT)) return;

        const grid_size_f = @as(f32, @floatFromInt(GRID_SIZE));
        const snapped_x = @round(mouse_pos.x / grid_size_f) * grid_size_f;
        const snapped_y = @round(mouse_pos.y / grid_size_f) * grid_size_f;
        const snapped_pos = rl.Vector2{ .x = snapped_x, .y = snapped_y };

        const match = getHoveredConnectionPoint(registry, mouse_pos);

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
                    state.interaction = .{ .DrawingWire = m.position };
                } else {
                    self.placeGate(registry, state, mouse_pos);
                }
            },
            .PlacingCompoundGate => |index| {
                if (match) |m| {
                    state.interaction = .{ .DrawingWire = m.position };
                } else {
                    if (index < state.compound_gates.items.len) {
                        const template = state.compound_gates.items[index];
                        factory.createCompoundGate(registry, self.allocator, template, snapped_pos, index, state.compound_gates.items);
                    }
                }
            },
            .Idle => {
                if (match) |m| {
                    state.interaction = .{ .DrawingWire = m.position };
                } else {
                    if (getHoveredGate(registry, mouse_pos)) |entity| {
                        var is_selected = false;
                        for (state.selected_entities.items) |e| {
                            if (e == entity) {
                                is_selected = true;
                                break;
                            }
                        }

                        if (!is_selected) {
                            if (!rl.IsKeyDown(rl.KEY_LEFT_SHIFT)) {
                                state.selected_entities.clearRetainingCapacity();
                            }
                            state.selected_entities.append(self.allocator, entity) catch {};
                        }

                        self.initial_entity_positions.clearRetainingCapacity();
                        for (state.selected_entities.items) |e| {
                            if (registry.tryGetConst(Transform, e)) |t| {
                                self.initial_entity_positions.put(e, t.position) catch {};
                            }
                        }
                        state.interaction = .{ .MovingSelection = mouse_pos };
                    } else {
                        if (!rl.IsKeyDown(rl.KEY_LEFT_SHIFT)) {
                            state.selected_entities.clearRetainingCapacity();
                        }
                        state.interaction = .{ .BoxSelecting = rl.Rectangle{ .x = mouse_pos.x, .y = mouse_pos.y, .width = 0, .height = 0 } };
                    }
                }
            },
            else => {},
        }
    }

    fn placeGate(self: *InputSystem, registry: *entt.Registry, state: *AppState, mouse_pos: rl.Vector2) void {
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

    fn destroyEntity(self: *InputSystem, registry: *entt.Registry, entity: entt.Entity) void {
        if (registry.tryGet(Gate, entity)) |g| {
            if (g.gate_type == .COMPOUND) {
                if (g.internal_state) |ptr| {
                    const state = @as(*CompoundState, @ptrCast(@alignCast(ptr)));
                    factory.destroyCompoundState(self.allocator, state);
                }
            }
        }
        registry.destroy(entity);
    }
};

// Helper Functions

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
            movePointIfMatch(&wire.start, g.getOutputPos(old_pos, 0), delta);
            movePointIfMatch(&wire.end, g.getOutputPos(old_pos, 0), delta);
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
            var i: u8 = 0;
            while (i < g.output_count) : (i += 1) {
                const out_pos = g.getOutputPos(t.position, i);
                if (rl.CheckCollisionPointCircle(mouse_pos, out_pos, pin_radius)) {
                    return .{ .position = out_pos };
                }
            }
        }

        if (g.gate_type != .INPUT) {
            var i: u8 = 0;
            while (i < g.input_count) : (i += 1) {
                const in_pos = g.getInputPos(t.position, i);
                if (rl.CheckCollisionPointCircle(mouse_pos, in_pos, pin_radius)) {
                    return .{ .position = in_pos };
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
        if (rl.CheckCollisionPointRec(mouse_pos, g.getRect(t.position))) {
            return entity;
        }
    }
    return null;
}

fn getHoveredWire(registry: *entt.Registry, mouse_pos: rl.Vector2) ?entt.Entity {
    var wire_view = registry.view(.{Wire}, .{});
    var wire_it = wire_view.entityIterator();
    while (wire_it.next()) |entity| {
        const wire = wire_view.getConst(entity);
        const pin_radius = 5.0;

        // Check endpoints
        if (rl.CheckCollisionPointCircle(mouse_pos, wire.start, pin_radius)) return entity;
        if (rl.CheckCollisionPointCircle(mouse_pos, wire.end, pin_radius)) return entity;

        // Check segment
        const ab = rl.Vector2Subtract(wire.end, wire.start);
        const ap = rl.Vector2Subtract(mouse_pos, wire.start);
        const len_sqr = rl.Vector2LengthSqr(ab);

        if (len_sqr > 0.0) {
            const t = rl.Vector2DotProduct(ap, ab) / len_sqr;
            const t_clamped = @max(0.0, @min(1.0, t));
            const closest = rl.Vector2Add(wire.start, rl.Vector2Scale(ab, t_clamped));

            if (rl.CheckCollisionPointCircle(mouse_pos, closest, pin_radius)) {
                return entity;
            }
        }
    }
    return null;
}

fn isMouseOverEntity(registry: *entt.Registry, entity: entt.Entity, mouse_pos: rl.Vector2) bool {
    if (!registry.valid(entity)) return false;
    if (registry.tryGetConst(Transform, entity)) |t| {
        if (registry.tryGetConst(Gate, entity)) |g| {
            return rl.CheckCollisionPointRec(mouse_pos, g.getRect(t.position));
        }
    }
    return false;
}