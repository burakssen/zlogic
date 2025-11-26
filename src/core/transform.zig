const rl = @import("raylib.zig").rl;

pub const Transform = struct {
    position: rl.Vector2,
    rotation: f32,
    scale: rl.Vector2,
};
