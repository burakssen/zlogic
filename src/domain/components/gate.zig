const rl = @import("raylib").rl;

pub const GateType = enum {
    AND,
    OR,
    NOT,
    INPUT,
    OUTPUT,
};

pub const Gate = struct {
    gate_type: GateType,
    width: f32 = 60,
    height: f32 = 40,
    inputs: [2]bool = .{ false, false },
    output: bool = false,

    pub fn getOutputPos(self: Gate, position: rl.Vector2) rl.Vector2 {
        return .{
            .x = position.x + self.width,
            .y = position.y + self.height * 0.5,
        };
    }

    pub fn getInputPos(self: Gate, position: rl.Vector2, index: usize) rl.Vector2 {
        if (self.gate_type == .OUTPUT) {
            return .{
                .x = position.x,
                .y = position.y + self.height * 0.5,
            };
        }
        const y_factor: f32 = if (self.gate_type == .NOT) 0.5 else if (index == 0) 0.0 else 1.0;
        return .{
            .x = position.x,
            .y = position.y + self.height * y_factor,
        };
    }
};
