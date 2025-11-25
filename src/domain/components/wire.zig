const rl = @import("raylib").rl;

pub const Wire = struct {
    start: rl.Vector2,
    end: rl.Vector2,
    active: bool = false,
};
