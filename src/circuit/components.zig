const std = @import("std");
const rl = @import("core").rl;
const entt = @import("core").entt;

// --- Logic/Data Components ---

pub const GateType = enum {
    AND,
    OR,
    NOT,
    INPUT,
    OUTPUT,
    COMPOUND,

    pub const ALL = [_]GateType{ .AND, .OR, .NOT, .INPUT, .OUTPUT };
};

pub const CompoundState = struct {
    registry: *entt.Registry,
    input_map: std.ArrayListUnmanaged(entt.Entity),
    output_map: std.ArrayListUnmanaged(entt.Entity),
};

pub const CompoundGateTemplate = struct {
    name: [32]u8,
    name_len: u8,
    gates: std.ArrayListUnmanaged(struct { type: GateType, offset: rl.Vector2, template_id: ?usize }),
    wires: std.ArrayListUnmanaged(struct { start_offset: rl.Vector2, end_offset: rl.Vector2 }),
};

pub const Gate = struct {
    gate_type: GateType,
    width: f32 = 60,
    height: f32 = 40,
    
    inputs: u16 = 0,
    outputs: u16 = 0,
    
    input_count: u8 = 2,
    output_count: u8 = 1,
    
    template_id: ?usize = null,
    internal_state: ?*anyopaque = null,

    pub fn init(gate_type: GateType) Gate {
        var self = Gate{
            .gate_type = gate_type,
        };
        
        switch (gate_type) {
            .NOT => self.input_count = 1,
            .INPUT => self.input_count = 0,
            .OUTPUT => self.output_count = 0,
            else => {},
        }
        return self;
    }

    pub fn getRect(self: Gate, position: rl.Vector2) rl.Rectangle {
        return .{
            .x = position.x,
            .y = position.y,
            .width = self.width,
            .height = self.height,
        };
    }

    pub fn getOutputPos(self: Gate, position: rl.Vector2, index: usize) rl.Vector2 {
        if (self.output_count <= 1) {
            return .{
                .x = position.x + self.width,
                .y = position.y + self.height * 0.5,
            };
        }
        
        const step = self.height / @as(f32, @floatFromInt(self.output_count + 1));
        return .{
            .x = position.x + self.width,
            .y = position.y + step * @as(f32, @floatFromInt(index + 1)),
        };
    }

    pub fn getInputPos(self: Gate, position: rl.Vector2, index: usize) rl.Vector2 {
        if (self.gate_type == .OUTPUT) {
            return .{
                .x = position.x,
                .y = position.y + self.height * 0.5,
            };
        }
        
        if (self.input_count == 1) {
             return .{
                .x = position.x,
                .y = position.y + self.height * 0.5,
            };
        } else if (self.input_count == 2 and self.gate_type != .COMPOUND) {
             const y_factor: f32 = if (index == 0) 0.25 else 0.75;
             return .{
                .x = position.x,
                .y = position.y + self.height * y_factor,
            };
        }

        const step = self.height / @as(f32, @floatFromInt(self.input_count + 1));
        return .{
            .x = position.x,
            .y = position.y + step * @as(f32, @floatFromInt(index + 1)),
        };
    }
    
    pub fn getInput(self: Gate, index: u4) bool {
        return (self.inputs & (@as(u16, 1) << index)) != 0;
    }
    
    pub fn setInput(self: *Gate, index: u4, val: bool) void {
        if (val) {
            self.inputs |= (@as(u16, 1) << index);
        } else {
            self.inputs &= ~(@as(u16, 1) << index);
        }
    }
    
    pub fn getOutput(self: Gate, index: u4) bool {
        return (self.outputs & (@as(u16, 1) << index)) != 0;
    }
    
    pub fn setOutput(self: *Gate, index: u4, val: bool) void {
        if (val) {
            self.outputs |= (@as(u16, 1) << index);
        } else {
            self.outputs &= ~(@as(u16, 1) << index);
        }
    }
};

pub const Wire = struct {
    start: rl.Vector2,
    end: rl.Vector2,
    active: bool = false,
};

pub const Label = struct {
    text: [32]u8 = undefined,
    len: usize = 0,
};
