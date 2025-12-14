const std = @import("std");
const Allocator = std.mem.Allocator;

pub const Cli = struct {
    stdout_buffer: [1024]u8 = undefined,
    logfile: ?std.fs.File = null,
    logname: ?[]const u8 = null,
    app_prefix: ?[]const u8 = null,
    show_timestamp: bool = false,
    debug_level: ?u2 = null,
    no_color: bool = false,
    theme: Theme = .pro,

    pub const Theme = enum {
        default,
        darker,
        pro,
        purple,
        blue,
        violetta,
    };

    pub fn parseTheme(self: *Cli, name: []const u8) ?Theme {
        _ = self;
        return std.meta.stringToEnum(Theme, name);
    }

    pub const MsgKind = enum {
        inf,
        wrn,
        err,
        hil,
        dbg,
        db2,
        db3,
        ok,
        snd,
        rok,
        run,
        st2,

        pub fn label(self: MsgKind) []const u8 {
            return switch (self) {
                .inf => "inf",
                .wrn => "wrn",
                .err => "err",
                .hil => "hil",
                .dbg => "dbg",
                .db2 => "db2",
                .db3 => "db3",
                .ok => "ok!",
                .run => "run",
                .snd => "snd",
                .rok => "rok",
                .st2 => "st2",
            };
        }

        pub fn colorize(
            self: MsgKind,
            theme: Theme,
            txt: []const u8,
            out: []u8,
        ) ![]const u8 {
            var stream = std.io.fixedBufferStream(out);
            var w = stream.writer();
            switch (theme) {
                .default => {
                    switch (self) {
                        .inf => try w.print("\x1b[38;5;189m{s}\x1b[0m", .{txt}),

                        .ok => try w.print("\x1b[38;5;119m{s}\x1b[0m", .{txt}),
                        .wrn => try w.print("\x1b[38;5;215m{s}\x1b[0m", .{txt}),
                        .err => try w.print("\x1b[38;5;204m{s}\x1b[0m", .{txt}),

                        .hil => try w.print("\x1b[38;5;105m{s}\x1b[0m", .{txt}),
                        .dbg => try w.print("\x1b[38;5;244m{s}\x1b[0m", .{txt}),
                        .db2 => try w.print("\x1b[38;5;242m{s}\x1b[0m", .{txt}),
                        .db3 => try w.print("\x1b[38;5;213m{s}\x1b[0m", .{txt}),

                        .run => try w.print("\x1b[38;5;45m{s}\x1b[0m", .{txt}),
                        .st2 => try w.print("\x1b[38;5;38m{s}\x1b[0m", .{txt}),
                        .snd => try w.print("\x1b[38;5;67m{s}\x1b[0m", .{txt}),
                        .rok => try w.print("\x1b[38;5;111m{s}\x1b[0m", .{txt}),
                    }
                },

                .darker => {
                    switch (self) {
                        .inf => try w.print("\x1b[38;5;246m{s}\x1b[0m", .{txt}),

                        .ok => try w.print("\x1b[38;5;119m{s}\x1b[0m", .{txt}),
                        .wrn => try w.print("\x1b[38;5;215m{s}\x1b[0m", .{txt}),
                        .err => try w.print("\x1b[38;5;204m{s}\x1b[0m", .{txt}),

                        .hil => try w.print("\x1b[38;5;105m{s}\x1b[0m", .{txt}),
                        .dbg => try w.print("\x1b[38;5;244m{s}\x1b[0m", .{txt}),
                        .db2 => try w.print("\x1b[38;5;242m{s}\x1b[0m", .{txt}),
                        .db3 => try w.print("\x1b[38;5;213m{s}\x1b[0m", .{txt}),

                        .run => try w.print("\x1b[38;5;32m{s}\x1b[0m", .{txt}),
                        .st2 => try w.print("\x1b[38;5;38m{s}\x1b[0m", .{txt}),

                        .snd => try w.print("\x1b[38;5;60m{s}\x1b[0m", .{txt}),
                        .rok => try w.print("\x1b[38;5;66m{s}\x1b[0m", .{txt}),
                    }
                },

                .pro => {
                    switch (self) {
                        .inf => try w.print("\x1b[38;5;189m{s}\x1b[0m", .{txt}),
                        .run => try w.print("\x1b[38;5;38m{s}\x1b[0m", .{txt}),
                        .snd => try w.print("\x1b[38;5;60m{s}\x1b[0m", .{txt}),
                        .rok => try w.print("\x1b[38;5;66m{s}\x1b[0m", .{txt}),
                        .ok => try w.print("\x1b[38;5;82m{s}\x1b[0m", .{txt}),
                        .st2 => try w.print("\x1b[38;5;61m{s}\x1b[0m", .{txt}),

                        .hil => try w.print("\x1b[38;5;153m{s}\x1b[0m", .{txt}),
                        .wrn => try w.print("\x1b[38;5;215m{s}\x1b[0m", .{txt}),
                        .err => try w.print("\x1b[38;5;203m{s}\x1b[0m", .{txt}),
                        .dbg => try w.print("\x1b[38;5;245m{s}\x1b[0m", .{txt}),
                        .db2 => try w.print("\x1b[38;5;243m{s}\x1b[0m", .{txt}),
                        .db3 => try w.print("\x1b[38;5;213m{s}\x1b[0m", .{txt}),
                    }
                },

                .purple => {
                    switch (self) {
                        .inf => try w.print("\x1b[38;5;189m{s}\x1b[0m", .{txt}),

                        .ok => try w.print("\x1b[38;5;119m{s}\x1b[0m", .{txt}),
                        .wrn => try w.print("\x1b[38;5;215m{s}\x1b[0m", .{txt}),
                        .err => try w.print("\x1b[38;5;204m{s}\x1b[0m", .{txt}),

                        .hil => try w.print("\x1b[38;5;147m{s}\x1b[0m", .{txt}),
                        .dbg => try w.print("\x1b[38;5;244m{s}\x1b[0m", .{txt}),
                        .db2 => try w.print("\x1b[38;5;242m{s}\x1b[0m", .{txt}),
                        .db3 => try w.print("\x1b[38;5;213m{s}\x1b[0m", .{txt}),

                        .run => try w.print("\x1b[38;5;105m{s}\x1b[0m", .{txt}),
                        .st2 => try w.print("\x1b[38;5;97m{s}\x1b[0m", .{txt}),
                        .snd => try w.print("\x1b[38;5;141m{s}\x1b[0m", .{txt}),
                        .rok => try w.print("\x1b[38;5;182m{s}\x1b[0m", .{txt}),
                    }
                },

                .blue => {
                    switch (self) {
                        .inf => try w.print("\x1b[38;5;153m{s}\x1b[0m", .{txt}),

                        .ok => try w.print("\x1b[38;5;119m{s}\x1b[0m", .{txt}),
                        .wrn => try w.print("\x1b[38;5;215m{s}\x1b[0m", .{txt}),
                        .err => try w.print("\x1b[38;5;204m{s}\x1b[0m", .{txt}),

                        .hil => try w.print("\x1b[38;5;69m{s}\x1b[0m", .{txt}),
                        .dbg => try w.print("\x1b[38;5;244m{s}\x1b[0m", .{txt}),
                        .db2 => try w.print("\x1b[38;5;242m{s}\x1b[0m", .{txt}),
                        .db3 => try w.print("\x1b[38;5;213m{s}\x1b[0m", .{txt}),

                        .run => try w.print("\x1b[38;5;75m{s}\x1b[0m", .{txt}),
                        .st2 => try w.print("\x1b[38;5;67m{s}\x1b[0m", .{txt}),
                        .snd => try w.print("\x1b[38;5;111m{s}\x1b[0m", .{txt}),
                        .rok => try w.print("\x1b[38;5;110m{s}\x1b[0m", .{txt}),
                    }
                },

                .violetta => {
                    switch (self) {
                        .inf => try w.print("\x1b[38;5;189m{s}\x1b[0m", .{txt}),

                        .run => try w.print("\x1b[38;5;110m{s}\x1b[0m", .{txt}),
                        .snd => try w.print("\x1b[38;5;140m{s}\x1b[0m", .{txt}),
                        .rok => try w.print("\x1b[38;5;146m{s}\x1b[0m", .{txt}),
                        .ok => try w.print("\x1b[38;5;165m{s}\x1b[0m", .{txt}),
                        .hil => try w.print("\x1b[38;5;105m{s}\x1b[0m", .{txt}),
                        .wrn => try w.print("\x1b[38;5;215m{s}\x1b[0m", .{txt}),
                        .err => try w.print("\x1b[38;5;204m{s}\x1b[0m", .{txt}),
                        .dbg => try w.print("\x1b[38;5;244m{s}\x1b[0m", .{txt}),
                        .db2 => try w.print("\x1b[38;5;242m{s}\x1b[0m", .{txt}),
                        .db3 => try w.print("\x1b[38;5;213m{s}\x1b[0m", .{txt}),
                        .st2 => try w.print("\x1b[38;5;103m{s}\x1b[0m", .{txt}),
                    }
                },
            }

            return out[0..try stream.getPos()];
        }
    };

    pub fn init(allocator: std.mem.Allocator) !*Cli {
        const ci = try allocator.create(Cli);
        ci.* = Cli{
            .debug_level = null,
            .show_timestamp = false,
        };
        return ci;
    }

    pub fn deinit(self: *Cli, allocator: std.mem.Allocator) void {
        if (self.logfile) |lf| {
            lf.close();
        }
        allocator.destroy(self);
    }

    pub fn enableLogmode(
        self: *Cli,
        name: []const u8,
    ) !void {
        self.logfile = try std.fs.cwd().createFile(name, .{});
        self.logname = name;
    }

    pub fn msg(
        self: *Cli,
        kind: MsgKind,
        comptime fmt: []const u8,
        args: anytype,
    ) void {
        self.printInternal(null, kind, fmt, args);
    }

    pub fn msg_subj(
        self: *Cli,
        kind: MsgKind,
        subject: []const u8,
        comptime fmt: []const u8,
        args: anytype,
    ) void {
        self.printInternal(subject, kind, fmt, args);
    }

    pub fn dbg(self: *Cli, comptime fmt: []const u8, args: anytype) void {
        if (self.debug_level) |d| {
            switch (d) {
                1 => self.printInternal(null, .dbg, fmt, args),
                2 => self.printInternal(null, .db2, fmt, args),
                3 => self.printInternal(null, .db3, fmt, args),
                else => {},
            }
        }
    }

    pub fn prompt(self: *Cli, comptime fmt: []const u8, args: anytype) void {
        var stdout_writer = std.fs.File.stdout().writer(&self.stdout_buffer);
        const stdout = &stdout_writer.interface;

        var buffer: [1024]u8 = undefined;
        var stream = std.io.fixedBufferStream(&buffer);
        var writer = stream.writer();

        _ = writer.print(fmt, args) catch {};
        const txt = buffer[0..writer.context.pos];

        if (!self.no_color) {
            var color_buf: [1024]u8 = undefined;
            const colored = MsgKind.run.colorize(
                self.theme,
                txt,
                &color_buf,
            ) catch txt;
            stdout.print("{s}", .{colored}) catch {};
        } else {
            stdout.print("{s}", .{txt}) catch {};
        }

        stdout.flush() catch {};
    }

    fn printInternal(
        self: *Cli,
        subject: ?[]const u8,
        kind: MsgKind,
        comptime fmt: []const u8,
        args: anytype,
    ) void {
        var stdout_writer = std.fs.File.stdout().writer(&self.stdout_buffer);
        const stdout = &stdout_writer.interface;
        if (self.debug_level) |d| {
            if (kind == .dbg and d < 1) return;
            if (kind == .db2 and d < 2) return;
            if (kind == .db3 and d < 3) return;
        } else {
            if (kind == .dbg or kind == .db2 or kind == .db3) return;
        }

        var buffer: [1024 * 128]u8 = undefined;

        var stream = std.io.fixedBufferStream(&buffer);
        var writer = stream.writer();

        if (self.show_timestamp) {
            const ts = std.time.nanoTimestamp();
            _ = writer.print("[{d}]", .{ts}) catch {};
        }

        if (self.app_prefix) |prefix| {
            _ = writer.print("[{s}]", .{prefix}) catch {};
        }

        _ = writer.print("[{s}]", .{kind.label()}) catch {};

        if (subject) |s| {
            _ = writer.print("[{s}]", .{s}) catch {};
        }

        _ = writer.print(" ", .{}) catch {};
        _ = writer.print(fmt, args) catch {};

        const txt = buffer[0..writer.context.pos];

        if (!self.no_color) {
            var color_buf: [1024 * 128]u8 = undefined;
            const colored = kind.colorize(self.theme, txt, &color_buf) catch txt;
            stdout.print("{s}\n", .{colored}) catch {};
        } else {
            stdout.print("{s}\n", .{txt}) catch {};
        }

        stdout.flush() catch {};

        if (self.logfile) |f| {
            _ = f.writeAll(txt) catch {};
            _ = f.writeAll("\n") catch {};
        }
    }

    pub fn is_dbg_level(self: *Cli, l: u2) bool {
        if (self.debug_level) |d| {
            if (d == l) return true;
        }
        return false;
    }
};
