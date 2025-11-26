const std = @import("std");
const rl = @import("core").rl;
const entt = @import("core").entt;
const components = @import("components.zig");
const Transform = @import("core").Transform;

const Gate = components.Gate;
const Wire = components.Wire;
const GateType = components.GateType;
const Label = components.Label;
const CompoundGateTemplate = components.CompoundGateTemplate;
const CompoundState = components.CompoundState;

pub fn createWire(registry: *entt.Registry, start: rl.Vector2, end: rl.Vector2) void {
    const entity = registry.create();
    registry.add(entity, Wire{ .start = start, .end = end });
}

pub fn createGate(registry: *entt.Registry, gate_type: GateType, position: rl.Vector2) void {
    const entity = registry.create();
    registry.add(entity, Transform{
        .position = position,
        .rotation = 0.0,
        .scale = .{ .x = 1.0, .y = 1.0 },
    });
    registry.add(entity, Gate.init(gate_type));
    registry.add(entity, Label{});
}

pub fn createCompoundGate(
    registry: *entt.Registry,
    allocator: std.mem.Allocator,
    template: CompoundGateTemplate,
    position: rl.Vector2,
    template_id: ?usize,
    all_templates: []const CompoundGateTemplate,
) void {
    // 1. Analyze counts
    var input_count: u8 = 0;
    var output_count: u8 = 0;
    for (template.gates.items) |g| {
        if (g.type == .INPUT) input_count += 1;
        if (g.type == .OUTPUT) output_count += 1;
    }

    // 2. Setup Internal State
    const internal_reg_ptr = allocator.create(entt.Registry) catch return;
    internal_reg_ptr.* = entt.Registry.init(allocator);

    var state_ptr = allocator.create(CompoundState) catch return;
    state_ptr.* = .{
        .registry = internal_reg_ptr,
        .input_map = .{},
        .output_map = .{},
    };

    const InternalInput = struct {
        e: entt.Entity,
        y: f32,
    };

    // 3. Populate Internal World
    var internal_inputs: std.ArrayList(InternalInput) = .empty;
    defer internal_inputs.deinit(allocator);
    var internal_outputs: std.ArrayList(InternalInput) = .empty;
    defer internal_outputs.deinit(allocator);

    for (template.gates.items) |g| {
        const pos = g.offset;

        if (g.type == .COMPOUND) {
            if (g.template_id) |tid| {
                if (tid < all_templates.len) {
                    createCompoundGate(internal_reg_ptr, allocator, all_templates[tid], pos, tid, all_templates);
                }
            }
        } else {
            const e = internal_reg_ptr.create();
            internal_reg_ptr.add(e, Transform{
                .position = pos,
                .rotation = 0.0,
                .scale = .{ .x = 1.0, .y = 1.0 },
            });
            internal_reg_ptr.add(e, Gate.init(g.type));

            if (g.type == .INPUT) {
                internal_inputs.append(allocator, .{ .e = e, .y = pos.y }) catch {};
            } else if (g.type == .OUTPUT) {
                internal_outputs.append(allocator, .{ .e = e, .y = pos.y }) catch {};
            }
        }
    }

    for (template.wires.items) |w| {
        const start = w.start_offset;
        const end = w.end_offset;
        createWire(internal_reg_ptr, start, end);
    }

    const sort_fn = struct {
        fn lessThan(_: void, a: InternalInput, b: InternalInput) bool {
            return a.y < b.y;
        }
    }.lessThan;

    std.sort.block(InternalInput, internal_inputs.items, {}, sort_fn);
    std.sort.block(InternalInput, internal_outputs.items, {}, sort_fn);

    for (internal_inputs.items) |item| {
        state_ptr.input_map.append(allocator, item.e) catch {};
    }
    for (internal_outputs.items) |item| {
        state_ptr.output_map.append(allocator, item.e) catch {};
    }

    // 4. Create Main Entity
    const entity = registry.create();
    registry.add(entity, Transform{
        .position = position,
        .rotation = 0.0,
        .scale = .{ .x = 1.0, .y = 1.0 },
    });

    var gate = Gate.init(.COMPOUND);
    gate.input_count = input_count;
    gate.output_count = output_count;
    gate.internal_state = state_ptr;
    gate.template_id = template_id;

    // Dynamic size based on pins
    const max_pins = @max(input_count, output_count);
    if (max_pins > 2) {
        gate.height = @as(f32, @floatFromInt(max_pins)) * 20.0;
    }

    registry.add(entity, gate);

    var label = Label{};
    if (template.name_len > 0) {
        const len = @min(template.name_len, 31);
        @memcpy(label.text[0..len], template.name[0..len]);
        label.len = @intCast(len);
    }
    registry.add(entity, label);
}

pub fn splitWire(registry: *entt.Registry, entity: entt.Entity, split_point: rl.Vector2) void {
    const wire = registry.get(Wire, entity);
    const start = wire.start;
    const end = wire.end;

    createWire(registry, start, split_point);
    createWire(registry, split_point, end);

    registry.destroy(entity);
}

pub fn destroyCompoundState(allocator: std.mem.Allocator, state: *CompoundState) void {
    var view = state.registry.view(.{Gate}, .{});
    var it = view.entityIterator();
    while (it.next()) |entity| {
        const gate = view.getConst(entity);
        if (gate.internal_state) |ptr| {
            const inner_state = @as(*CompoundState, @ptrCast(@alignCast(ptr)));
            destroyCompoundState(allocator, inner_state);
        }
    }

    state.registry.deinit();
    allocator.destroy(state.registry);
    state.input_map.deinit(allocator);
    state.output_map.deinit(allocator);
    allocator.destroy(state);
}
