const std = @import("std");
const Allocator = std.mem.Allocator;

/// Structured logging utility for terminal and file output.
///
/// Purpose:
/// - Print colorized messages by severity and category.
/// - Optionally include timestamps and app prefixes.
/// - Optionally duplicate output to a log file (uncolored).
///
/// Features:
/// - Color-coded severities (info, warn, error, debug, etc.).
/// - Themes to control palette.
/// - Timestamp and app prefix toggles.
/// - File logging of plain text.
///
/// Usage:
/// - Initialize with Cli.init().
/// - Use msg(), msg_subj(), or dbg() to emit messages.
/// - Use enableLogmode() to start file logging.
/// - Call deinit() to release resources. (close logfile)
pub const Cli = struct {
    stdout_buffer: [1024]u8 = undefined,
    logfile: ?std.fs.File = null,
    logname: ?[]const u8 = null,
    app_prefix: ?[]const u8 = null,
    show_timestamp: bool = false,
    debug_level: ?u2 = null,
    no_color: bool = false,
    theme: Theme = .pro,

    /// Available color themes for terminal output.
    ///
    /// Purpose:
    /// - Select a palette used by MsgKind.colorize().
    pub const Theme = enum {
        default,
        darker,
        pro,
        purple,
        blue,
        violetta,
    };

    /// Parse a theme name from a string.
    ///
    /// Purpose:
    /// - Convert user input into a Theme value.
    ///
    /// Parameters:
    /// - `name`: Case-sensitive enum name.
    ///
    /// Returns:
    /// - Theme on success, null on no match.
    pub fn parseTheme(self: *Cli, name: []const u8) ?Theme {
        _ = self;
        return std.meta.stringToEnum(Theme, name);
    }

    /// Message severity/category.
    ///
    /// Purpose:
    /// - Drive label text and color mapping.
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

        /// Return short label string for the kind.
        ///
        /// Returns:
        /// - Lowercase label (e.g. "inf", "err").
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

        /// Apply ANSI color codes to text based on theme and kind.
        ///
        /// Purpose:
        /// - Produce a colored version of `txt` for terminal output.
        ///
        /// Parameters:
        /// - `theme`: Selected color theme.
        /// - `txt`: Text to colorize.
        /// - `out`: Destination buffer.
        ///
        /// Returns:
        /// - Slice of `out` containing the colored text.
        ///
        /// Errors:
        /// - Propagates I/O errors from the writer.
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

    /// Create a new Cli with defaults.
    ///
    /// Purpose:
    /// - Allocate and initialize a Cli instance.
    ///
    /// Parameters:
    /// - `allocator`: For allocation of the instance.
    ///
    /// Returns:
    /// - Pointer to Cli with defaults applied.
    ///
    /// Errors:
    /// - error.OutOfMemory on allocation failure.
    pub fn init(allocator: std.mem.Allocator) !*Cli {
        const ci = try allocator.create(Cli);
        ci.* = Cli{
            .debug_level = null,
            .show_timestamp = false,
        };
        return ci;
    }

    /// Destroy the instance and close the log file if open.
    ///
    /// Purpose:
    /// - Release resources owned by Cli.
    ///
    /// Parameters:
    /// - `allocator`: Allocator that owns the instance.
    pub fn deinit(self: *Cli, allocator: std.mem.Allocator) void {
        if (self.logfile) |lf| {
            lf.close();
        }
        allocator.destroy(self);
    }

    /// Enable log-to-file mode by creating a file.
    ///
    /// Purpose:
    /// - Duplicate console output into `name` (uncolored).
    ///
    /// Parameters:
    /// - `name`: Path of log file to create (cwd-relative).
    ///
    /// Errors:
    /// - Propagates file I/O errors.
    pub fn enableLogmode(
        self: *Cli,
        name: []const u8,
    ) !void {
        self.logfile = try std.fs.cwd().createFile(name, .{});
        self.logname = name;
    }

    /// Print a message with the given kind.
    ///
    /// Purpose:
    /// - Core emitter for info/warn/error/etc.
    pub fn msg(
        self: *Cli,
        kind: MsgKind,
        comptime fmt: []const u8,
        args: anytype,
    ) void {
        self.printInternal(null, kind, fmt, args);
    }

    /// Print a message with kind and subject tag.
    ///
    /// Purpose:
    /// - Attach a subject (e.g. "mytool|init") to the line.
    pub fn msg_subj(
        self: *Cli,
        kind: MsgKind,
        subject: []const u8,
        comptime fmt: []const u8,
        args: anytype,
    ) void {
        self.printInternal(subject, kind, fmt, args);
    }

    /// Print a debug message if enabled.
    ///
    /// Purpose:
    /// - Emit .dbg/.db2/.db3 depending on debug_level.
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

    /// Print a prompt without trailing newline.
    ///
    /// Purpose:
    /// - Interactive prompts where user input follows on same line.
    ///
    /// Behavior:
    /// - Prints with .run kind color, no newline.
    /// - Does NOT log to file (prompts are transient).
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
            const colored = MsgKind.run.colorize(self.theme, txt, &color_buf) catch txt;
            stdout.print("{s}", .{colored}) catch {};
        } else {
            stdout.print("{s}", .{txt}) catch {};
        }

        stdout.flush() catch {};
    }

    /// Format, colorize, print, and optionally log to file.
    ///
    /// Purpose:
    /// - Shared path for all message printing.
    ///
    /// Behavior:
    /// - Respects debug_level for dbg/db2/db3.
    /// - Adds timestamp and app prefix when enabled.
    /// - Applies color unless no_color is true.
    /// - Writes plain text to logfile if enabled.
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

    /// Check whether the current debug level equals `l`.
    ///
    /// Purpose:
    /// - Allow quick checks in higher-level code.
    ///
    /// Parameters:
    /// - `l`: Level to compare (1..3).
    ///
    /// Returns:
    /// - true if enabled at exactly that level.
    pub fn is_dbg_level(self: *Cli, l: u2) bool {
        if (self.debug_level) |d| {
            if (d == l) return true;
        }
        return false;
    }
};
