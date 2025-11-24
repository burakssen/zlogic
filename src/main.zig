const std = @import("std");

const App = @import("app");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const app = try App.init(allocator, .{ .x = 1280, .y = 720 }, "zlogic");
    defer app.deinit();

    app.run();
}
