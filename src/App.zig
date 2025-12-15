//! Application lifecycle and main loop.

const std = @import("std");
const version = @import("version.zig");
const Cli = @import("Cli.zig").Cli;
const MemoryStoreSqlite = @import("MemoryStoreSqlite.zig").MemoryStoreSqlite;
const ProviderOllama = @import("ProviderOllama.zig").ProviderOllama;
const EventSystem = @import("EventSystem.zig").EventSystem;
const Commands = @import("Commands.zig");
const ChatEngine = @import("ChatEngine.zig");

const ConfigConn = @import("ConfigConnection.zig").ConfigConnection;
const ConfigSys = @import("ConfigSystem.zig").ConfigSystem;
const ConfigIdent = @import("ConfigIdentity.zig").ConfigIdentity;

pub const App = struct {
    cli: *Cli,
    store: MemoryStoreSqlite,
    provider: ProviderOllama,
    events: EventSystem,
    conn: ConfigConn,
    sys: ConfigSys,
    ident: ConfigIdent,

    pub fn init(allocator: std.mem.Allocator, cli: *Cli) !App {
        const conn = ConfigConn{};
        const sys = ConfigSys{};
        const ident = ConfigIdent{};

        cli.msg(.inf, "Starting up ...", .{});

        var provider = try ProviderOllama.init(
            allocator,
            conn.ollama_url,
            conn.ollama_model,
        );
        errdefer provider.deinit(allocator);

        var store = try MemoryStoreSqlite.init(conn.database_path);
        errdefer store.deinit();

        try store.ensureSchema();
        cli.msg(.ok, "SQLite store: {s}", .{conn.database_path});

        return App{
            .cli = cli,
            .store = store,
            .provider = provider,
            .events = undefined,
            .conn = conn,
            .sys = sys,
            .ident = ident,
        };
    }

    pub fn initEvents(self: *App) void {
        self.events = EventSystem.init(&self.store, null);
    }

    pub fn deinit(self: *App, allocator: std.mem.Allocator) void {
        self.store.deinit();
        self.provider.deinit(allocator);
    }

    pub fn run(self: *App, allocator: std.mem.Allocator) !void {
        self.printBanner();

        const stdin: std.fs.File = .{ .handle = std.posix.STDIN_FILENO };
        var line_buf: [4096]u8 = undefined;

        while (true) {
            self.cli.prompt("You: ", .{});

            const line_opt = try readLine(stdin, &line_buf);
            if (line_opt == null) break;

            const line = std.mem.trimRight(u8, line_opt.?, "\r\n");
            if (line.len == 0) continue;

            switch (try Commands.execute(allocator, self, line)) {
                .quit => break,
                .handled => continue,
                .not_command => {},
            }

            try ChatEngine.processTurn(allocator, self, line);
        }
    }

    fn printBanner(self: *App) void {
        self.cli.msg(.hil, "{s} {s}", .{ self.ident.name, version.version });
        self.cli.msg(.inf, "Ollama provider ({s}).", .{self.conn.ollama_model});
        self.cli.msg(.inf, "Type /help for commands.", .{});
    }
};

fn readLine(file: std.fs.File, buf: []u8) !?[]u8 {
    var i: usize = 0;
    while (i < buf.len) {
        var byte: [1]u8 = undefined;
        const n = file.read(&byte) catch |err| {
            if (err == error.WouldBlock) continue;
            return err;
        };
        if (n == 0) {
            if (i == 0) return null;
            return buf[0..i];
        }
        if (byte[0] == '\n') {
            return buf[0..i];
        }
        buf[i] = byte[0];
        i += 1;
    }
    return buf[0..i];
}
