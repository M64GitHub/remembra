//! REMEMBRA HTTP server entry point.
//! Provides Ollama-compatible API for web UI integration.

const std = @import("std");
const App = @import("App.zig").App;
const Cli = @import("Cli.zig").Cli;
const HttpServer = @import("HttpServer.zig").HttpServer;
const ConfigSys = @import("ConfigSystem.zig").ConfigSystem;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const sys = ConfigSys{};

    var cli = try Cli.init(allocator);
    defer cli.deinit(allocator);
    cli.app_prefix = "SERVER";
    cli.show_timestamp = sys.show_timestamp;
    cli.debug_level = sys.debug_level;
    try cli.enableLogmode(sys.log_file);

    var app = try App.init(allocator, cli);
    defer app.deinit(allocator);
    app.initEvents();

    var server = try HttpServer.init();
    defer server.deinit();

    cli.msg(.hil, "REMEMBRA Server", .{});
    cli.msg(.inf, "Ollama-compatible API on http://127.0.0.1:8080", .{});
    cli.msg(.inf, "POST /api/chat - Chat endpoint", .{});
    cli.msg(.inf, "GET /health - Health check", .{});

    try server.run(allocator, &app);
}
