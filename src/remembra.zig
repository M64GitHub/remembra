const std = @import("std");
const App = @import("App.zig").App;
const Cli = @import("Cli.zig").Cli;
const ConfigSys = @import("ConfigSystem.zig").ConfigSystem;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const sys = ConfigSys{};

    var cli = try Cli.init(allocator);
    defer cli.deinit(allocator);
    cli.app_prefix = sys.app_prefix;
    cli.show_timestamp = sys.show_timestamp;
    cli.debug_level = sys.debug_level;
    try cli.enableLogmode(sys.log_file);

    var app = try App.init(allocator, cli);
    defer app.deinit(allocator);

    try app.run(allocator);
}
