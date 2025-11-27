const rl = @import("raylib.zig").rl;

pub const Theme = struct {
    pub const grid_size: i32 = 10;

    pub const background = rl.Color{ .r = 30, .g = 30, .b = 46, .a = 255 }; // Dark Blue/Grey
    pub const grid_line = rl.Color{ .r = 49, .g = 50, .b = 68, .a = 255 }; // Lighter Grey
    
    pub const gate_body = rl.Color{ .r = 69, .g = 71, .b = 90, .a = 255 };
    pub const ic_body = rl.Color{ .r = 45, .g = 45, .b = 60, .a = 255 };
    pub const gate_border = rl.Color{ .r = 147, .g = 153, .b = 178, .a = 255 };
    pub const gate_text = rl.Color{ .r = 205, .g = 214, .b = 244, .a = 255 };
    
    pub const wire_inactive = rl.Color{ .r = 88, .g = 91, .b = 112, .a = 255 };
    pub const wire_active = rl.Color{ .r = 166, .g = 227, .b = 161, .a = 255 }; // Green
    
    pub const toolbar_bg = rl.Color{ .r = 24, .g = 24, .b = 37, .a = 255 };
    pub const button_inactive = rl.Color{ .r = 49, .g = 50, .b = 68, .a = 255 };
    pub const button_active = rl.Color{ .r = 88, .g = 91, .b = 112, .a = 255 };
    pub const button_hover = rl.Color{ .r = 69, .g = 71, .b = 90, .a = 255 };
    pub const button_border = rl.Color{ .r = 147, .g = 153, .b = 178, .a = 255 };
    
    pub const Layout = struct {
        pub const toolbar_height: f32 = 60.0;
        pub const button_width: f32 = 80.0;
        pub const button_padding: f32 = 10.0;
        pub const button_margin_top: f32 = 10.0;

        pub const menu_width: f32 = 140.0;
        pub const menu_item_height: f32 = 36.0;
    };
};
