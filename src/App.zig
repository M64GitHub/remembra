//! Application lifecycle and main loop.

const std = @import("std");
const version = @import("version.zig");
const Cli = @import("Cli.zig").Cli;
const MemoryStoreSqlite = @import("MemoryStoreSqlite.zig").MemoryStoreSqlite;
const ProviderOllama = @import("ProviderOllama.zig").ProviderOllama;
const EventSystem = @import("EventSystem.zig").EventSystem;
const Commands = @import("Commands.zig");
const ChatEngine = @import("ChatEngine.zig");
const Types = @import("Types.zig");

const ConfigConn = @import("ConfigConnection.zig").ConfigConnection;
const ConfigSys = @import("ConfigSystem.zig").ConfigSystem;
const ConfigIdent = @import("ConfigIdentity.zig").ConfigIdentity;
const IdleThinker = @import("IdleThinker.zig").IdleThinker;

pub const LastContext = struct {
    system_prompt: []const u8 = "",
    memory_count: usize = 0,
    recent_count: usize = 0,
    max_recent_messages: usize = 24,
    timestamp_ms: i64 = 0,
};

pub const App = struct {
    cli: *Cli,
    store: MemoryStoreSqlite,
    provider: ProviderOllama,
    events: EventSystem,
    conn: ConfigConn,
    sys: ConfigSys,
    ident: ConfigIdent,
    max_recent_messages: usize = 24,
    reflection_enabled: bool = true,
    include_ai_name: bool = true,
    last_context: LastContext = .{},
    last_context_prompt_buf: [32768]u8 = undefined,

    // Buffers for persona data loaded from DB
    persona_name_buf: [64]u8 = undefined,
    persona_name_len: usize = 0,
    prompt_system_spine_buf: [4096]u8 = undefined,
    prompt_system_spine_len: usize = 0,
    prompt_reflector_system_buf: [4096]u8 = undefined,
    prompt_reflector_system_len: usize = 0,
    prompt_reflector_no_ops_buf: [1024]u8 = undefined,
    prompt_reflector_no_ops_len: usize = 0,
    prompt_idle_thinker_buf: [2048]u8 = undefined,
    prompt_idle_thinker_len: usize = 0,
    prompt_episode_compactor_buf: [2048]u8 = undefined,
    prompt_episode_compactor_len: usize = 0,
    persona_kernel_buf: [2048]u8 = undefined,
    persona_kernel_len: usize = 0,
    persona_tone_buf: [256]u8 = undefined,
    persona_tone_len: usize = 0,
    persona_idle_params: IdleThinker.Params = .{},

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

        const max_recent = store.getMaxRecentMessages();
        const reflection = store.getReflectionEnabled();

        return App{
            .cli = cli,
            .store = store,
            .provider = provider,
            .events = undefined,
            .conn = conn,
            .sys = sys,
            .ident = ident,
            .max_recent_messages = max_recent,
            .reflection_enabled = reflection,
        };
    }

    pub fn initEvents(self: *App) void {
        self.events = EventSystem.init(&self.store, null);
    }

    pub fn setMaxRecentMessages(self: *App, count: usize) !void {
        try self.store.setMaxRecentMessages(count);
        self.max_recent_messages = count;
    }

    pub fn setReflectionEnabled(self: *App, enabled: bool) !void {
        try self.store.setReflectionEnabled(enabled);
        self.reflection_enabled = enabled;
    }

    pub fn deinit(self: *App, allocator: std.mem.Allocator) void {
        self.store.deinit();
        self.provider.deinit(allocator);
    }

    pub fn reloadActiveProvider(
        self: *App,
        allocator: std.mem.Allocator,
    ) !void {
        const MemStore = @import("MemoryStoreSqlite.zig");
        const id = self.store.getActiveProviderId() orelse return;

        const profile = try self.store.getProviderProfile(allocator, id) orelse
            return;
        defer MemStore.freeProviderProfile(allocator, profile);

        self.provider.deinit(allocator);
        self.provider = try ProviderOllama.init(
            allocator,
            profile.ollama_url,
            profile.model,
        );

        self.cli.msg(
            .inf,
            "Provider reloaded: {s} ({s})",
            .{ profile.name, profile.model },
        );
    }

    pub fn reloadActivePersona(
        self: *App,
        allocator: std.mem.Allocator,
    ) !void {
        const MemStore = @import("MemoryStoreSqlite.zig");
        const id = self.store.getActivePersonaId() orelse return;

        const profile = try self.store.getPersonaProfile(allocator, id) orelse
            return;
        defer MemStore.freePersonaStrings(allocator, profile);

        // Update LLM parameters
        self.ident.llm_chat = .{
            .temperature = profile.llm_chat.temperature,
            .max_tokens = profile.llm_chat.max_tokens,
        };
        self.ident.llm_reflection = .{
            .temperature = profile.llm_reflection.temperature,
            .max_tokens = profile.llm_reflection.max_tokens,
        };
        self.ident.llm_idle = .{
            .temperature = profile.llm_idle.temperature,
            .max_tokens = profile.llm_idle.max_tokens,
        };
        self.ident.llm_episode = .{
            .temperature = profile.llm_episode.temperature,
            .max_tokens = profile.llm_episode.max_tokens,
        };
        self.ident.confidence_user_notes = profile.conf_user_notes;
        self.ident.confidence_episodes = profile.conf_episodes;
        self.ident.confidence_idle_thoughts = profile.conf_idle;
        self.ident.confidence_min_governor = profile.conf_governor;

        // Update idle thinker params from persona
        self.persona_idle_params = .{
            .idle_threshold_ms = @as(i64, profile.idle_threshold_min) *
                60 * 1000,
            .min_msgs_for_compaction = @intCast(profile.compaction_threshold),
            .min_ms_between_thoughts = @as(i64, profile.thought_interval_min) *
                60 * 1000,
        };

        // Update AI name
        const name_len = @min(profile.ai_name.len, self.persona_name_buf.len);
        @memcpy(
            self.persona_name_buf[0..name_len],
            profile.ai_name[0..name_len],
        );
        self.persona_name_len = name_len;
        self.ident.name = self.persona_name_buf[0..self.persona_name_len];

        // Update persona kernel
        const kernel_len = @min(
            profile.persona_kernel.len,
            self.persona_kernel_buf.len,
        );
        @memcpy(
            self.persona_kernel_buf[0..kernel_len],
            profile.persona_kernel[0..kernel_len],
        );
        self.persona_kernel_len = kernel_len;
        self.ident.persona_kernel = self.persona_kernel_buf[0..kernel_len];

        // Update tone
        const tone_len = @min(profile.tone.len, self.persona_tone_buf.len);
        @memcpy(
            self.persona_tone_buf[0..tone_len],
            profile.tone[0..tone_len],
        );
        self.persona_tone_len = tone_len;
        self.ident.default_tone = self.persona_tone_buf[0..tone_len];

        // Update include_ai_name flag
        self.include_ai_name = profile.include_ai_name;

        // Load and update prompts from DB
        var prompts = self.store.getPersonaPrompts(allocator, id) catch {
            self.cli.msg(.wrn, "Failed to load prompts", .{});
            return;
        };
        defer {
            var iter = prompts.iterator();
            while (iter.next()) |entry| {
                allocator.free(entry.key_ptr.*);
                allocator.free(entry.value_ptr.*);
            }
            prompts.deinit();
        }

        self.copyPromptToBuf(
            &prompts,
            "system_spine",
            &self.prompt_system_spine_buf,
            &self.prompt_system_spine_len,
            &self.ident.prompts.system_spine,
        );
        self.copyPromptToBuf(
            &prompts,
            "reflector_system",
            &self.prompt_reflector_system_buf,
            &self.prompt_reflector_system_len,
            &self.ident.prompts.reflector_system,
        );
        self.copyPromptToBuf(
            &prompts,
            "reflector_no_ops",
            &self.prompt_reflector_no_ops_buf,
            &self.prompt_reflector_no_ops_len,
            &self.ident.prompts.reflector_no_ops,
        );
        self.copyPromptToBuf(
            &prompts,
            "idle_thinker",
            &self.prompt_idle_thinker_buf,
            &self.prompt_idle_thinker_len,
            &self.ident.prompts.idle_thinker,
        );
        self.copyPromptToBuf(
            &prompts,
            "episode_compactor",
            &self.prompt_episode_compactor_buf,
            &self.prompt_episode_compactor_len,
            &self.ident.prompts.episode_compactor,
        );

        self.cli.msg(.inf, "Persona reloaded: {s}", .{profile.name});
    }

    fn copyPromptToBuf(
        self: *App,
        prompts: *std.StringHashMap([]u8),
        name: []const u8,
        buf: []u8,
        len: *usize,
        target: *[]const u8,
    ) void {
        _ = self;
        if (prompts.get(name)) |val| {
            const copy_len = @min(val.len, buf.len);
            @memcpy(buf[0..copy_len], val[0..copy_len]);
            len.* = copy_len;
            target.* = buf[0..copy_len];
        }
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
