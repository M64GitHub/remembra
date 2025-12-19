//! SQLite-backed memory store for REMEMBRA persistence.

const std = @import("std");
const Types = @import("Types.zig");
const MemoryPolicy = @import("MemoryPolicy.zig").MemoryPolicy;
const sqlite = @import("sqlite.zig");
const c = sqlite.c;
const config_ident = @import("ConfigIdentity.zig");
const ConfigIdentity = config_ident.ConfigIdentity;
const PromptTemplates = config_ident.PromptTemplates;

pub const SCHEMA =
    \\PRAGMA journal_mode=WAL;
    \\PRAGMA synchronous=NORMAL;
    \\
    \\CREATE TABLE IF NOT EXISTS meta (
    \\    key   TEXT PRIMARY KEY,
    \\    value TEXT NOT NULL
    \\);
    \\
    \\CREATE TABLE IF NOT EXISTS messages (
    \\    id            INTEGER PRIMARY KEY AUTOINCREMENT,
    \\    persona_id    INTEGER NOT NULL,
    \\    role          INTEGER NOT NULL,
    \\    content       TEXT NOT NULL,
    \\    created_at_ms INTEGER NOT NULL
    \\);
    \\
    \\CREATE TABLE IF NOT EXISTS memory_items (
    \\    id            INTEGER PRIMARY KEY AUTOINCREMENT,
    \\    persona_id    INTEGER NOT NULL,
    \\    kind          INTEGER NOT NULL,
    \\    subject       TEXT NOT NULL,
    \\    predicate     TEXT NOT NULL,
    \\    object        TEXT NOT NULL,
    \\    confidence    REAL NOT NULL,
    \\    is_active     INTEGER NOT NULL,
    \\    created_at_ms INTEGER NOT NULL,
    \\    updated_at_ms INTEGER NOT NULL
    \\);
    \\
    \\CREATE TABLE IF NOT EXISTS identity_entries (
    \\    id            INTEGER PRIMARY KEY AUTOINCREMENT,
    \\    persona_id    INTEGER NOT NULL,
    \\    key           TEXT NOT NULL,
    \\    value         TEXT NOT NULL,
    \\    created_at_ms INTEGER NOT NULL,
    \\    UNIQUE(persona_id, key)
    \\);
    \\
    \\CREATE TABLE IF NOT EXISTS events (
    \\    id            INTEGER PRIMARY KEY AUTOINCREMENT,
    \\    persona_id    INTEGER NOT NULL,
    \\    kind          INTEGER NOT NULL,
    \\    timestamp_ms  INTEGER NOT NULL,
    \\    subject       TEXT NOT NULL,
    \\    details       TEXT NOT NULL,
    \\    session_id    TEXT
    \\);
    \\
    \\CREATE INDEX IF NOT EXISTS idx_messages_persona
    \\    ON messages(persona_id, id);
    \\CREATE INDEX IF NOT EXISTS idx_mem_active
    \\    ON memory_items(persona_id, is_active, subject, predicate);
    \\CREATE INDEX IF NOT EXISTS idx_mem_updated
    \\    ON memory_items(persona_id, updated_at_ms);
    \\CREATE INDEX IF NOT EXISTS idx_events_time
    \\    ON events(persona_id, timestamp_ms);
    \\CREATE INDEX IF NOT EXISTS idx_events_kind
    \\    ON events(persona_id, kind);
    \\
    \\CREATE TABLE IF NOT EXISTS provider_profiles (
    \\    id            INTEGER PRIMARY KEY AUTOINCREMENT,
    \\    name          TEXT NOT NULL UNIQUE,
    \\    ollama_url    TEXT NOT NULL,
    \\    model         TEXT NOT NULL,
    \\    size          INTEGER NOT NULL DEFAULT 0,
    \\    digest        TEXT NOT NULL DEFAULT '',
    \\    modified_at   TEXT NOT NULL DEFAULT '',
    \\    created_at_ms INTEGER NOT NULL
    \\);
    \\
    \\CREATE TABLE IF NOT EXISTS persona_profiles (
    \\    id            INTEGER PRIMARY KEY AUTOINCREMENT,
    \\    name          TEXT NOT NULL UNIQUE,
    \\    ai_name       TEXT NOT NULL,
    \\    tone          TEXT NOT NULL,
    \\    persona_kernel TEXT NOT NULL DEFAULT '',
    \\    llm_chat_temp      REAL NOT NULL,
    \\    llm_chat_tokens    INTEGER NOT NULL,
    \\    llm_reflect_temp   REAL NOT NULL,
    \\    llm_reflect_tokens INTEGER NOT NULL,
    \\    llm_idle_temp      REAL NOT NULL,
    \\    llm_idle_tokens    INTEGER NOT NULL,
    \\    llm_episode_temp   REAL NOT NULL,
    \\    llm_episode_tokens INTEGER NOT NULL,
    \\    conf_user_notes      REAL NOT NULL,
    \\    conf_episodes        REAL NOT NULL,
    \\    conf_idle            REAL NOT NULL,
    \\    conf_governor        REAL NOT NULL,
    \\    idle_threshold_min   INTEGER NOT NULL DEFAULT 15,
    \\    thought_interval_min INTEGER NOT NULL DEFAULT 60,
    \\    compaction_threshold INTEGER NOT NULL DEFAULT 6,
    \\    include_ai_name      INTEGER NOT NULL DEFAULT 1,
    \\    created_at_ms        INTEGER NOT NULL
    \\);
    \\
    \\CREATE TABLE IF NOT EXISTS identity_presets (
    \\    id            INTEGER PRIMARY KEY AUTOINCREMENT,
    \\    name          TEXT NOT NULL UNIQUE,
    \\    text          TEXT NOT NULL,
    \\    created_at_ms INTEGER NOT NULL
    \\);
    \\
    \\CREATE TABLE IF NOT EXISTS store_items (
    \\    id            INTEGER PRIMARY KEY AUTOINCREMENT,
    \\    persona_id    INTEGER NOT NULL,
    \\    content       TEXT NOT NULL,
    \\    source_msg_id INTEGER,
    \\    created_at_ms INTEGER NOT NULL,
    \\    updated_at_ms INTEGER NOT NULL
    \\);
    \\
    \\CREATE TABLE IF NOT EXISTS bookmarks (
    \\    id            INTEGER PRIMARY KEY AUTOINCREMENT,
    \\    persona_id    INTEGER NOT NULL,
    \\    message_id    INTEGER NOT NULL,
    \\    created_at_ms INTEGER NOT NULL,
    \\    UNIQUE(persona_id, message_id)
    \\);
    \\
    \\CREATE INDEX IF NOT EXISTS idx_store_persona
    \\    ON store_items(persona_id, id);
    \\CREATE INDEX IF NOT EXISTS idx_bookmarks_persona
    \\    ON bookmarks(persona_id, message_id);
;

pub const MemoryStoreSqlite = struct {
    db: sqlite.SqliteDb,
    obj_buf: [4096]u8 = undefined,
    obj_len: usize = 0,

    pub fn init(path: [*:0]const u8) !MemoryStoreSqlite {
        const db = try sqlite.SqliteDb.open(path);
        return .{ .db = db };
    }

    pub fn deinit(self: *MemoryStoreSqlite) void {
        self.db.close();
    }

    pub fn ensureSchema(self: *MemoryStoreSqlite) !void {
        try self.db.exec(SCHEMA);
        try self.setMetaDefault("episode_cutoff_index", "0");
        try self.setMetaDefault("time_offset_ms", "0");
        try self.setMetaDefault("last_user_msg_ms", "0");
        try self.setMetaDefault("last_idle_think_ms", "0");
        try self.setMetaDefault("active_provider_id", "0");
        try self.setMetaDefault("active_persona_id", "0");
        try self.setMetaDefault("max_recent_messages", "24");
        try self.setMetaDefault("reflection_enabled", "1");
        try self.seedDefaultProfiles();
        try self.seedIdentityPresets();
    }

    fn seedDefaultProfiles(self: *MemoryStoreSqlite) !void {
        // Provider: create if none exist
        const prov_count = try self.scalarI64(
            "SELECT COUNT(*) FROM provider_profiles;",
        );
        if (prov_count == 0) {
            const provider_id = try self.createProviderProfile(
                "local-ollama",
                "http://127.0.0.1:11434",
                "llama3.2",
                0,
                "",
                "",
            );
            try self.setMetaI64("active_provider_id", provider_id);
        }

        // Persona: check if we need to create a default
        const need_default = blk: {
            const count = try self.scalarI64(
                "SELECT COUNT(*) FROM persona_profiles;",
            );
            if (count == 0) break :blk true;

            const active_id = self.getActivePersonaId() orelse break :blk true;

            // Check if active ID exists in DB
            const stmt = try self.db.prepare(
                "SELECT COUNT(*) FROM persona_profiles WHERE id = ?;",
            );
            defer sqlite.finalize(stmt);
            sqlite.bindInt64(stmt, 1, active_id);
            if (sqlite.step(stmt) != c.SQLITE_ROW) break :blk true;
            const exists = sqlite.columnInt64(stmt, 0);
            break :blk exists == 0;
        };

        if (need_default) {
            const ident = ConfigIdentity{};
            const persona_id = try self.createPersonaProfile(.{
                .name = "remembra-default",
                .ai_name = "REMEMBRA",
                .tone = "helpful, concise, grounded, engaging",
                .persona_kernel = ident.persona_kernel,
                .llm_chat = .{ .temperature = 0.7, .max_tokens = 256 },
                .llm_reflection = .{ .temperature = 0.2, .max_tokens = 512 },
                .llm_idle = .{ .temperature = 0.4, .max_tokens = 160 },
                .llm_episode = .{ .temperature = 0.2, .max_tokens = 512 },
                .conf_user_notes = 0.7,
                .conf_episodes = 0.85,
                .conf_idle = 0.55,
                .conf_governor = 0.6,
            });
            try self.setMetaI64("active_persona_id", persona_id);

            // Store default prompts in DB
            const defaults = PromptTemplates{};
            try self.setPersonaPrompt(persona_id, "system_spine", defaults.system_spine);
            try self.setPersonaPrompt(persona_id, "reflector_system", defaults.reflector_system);
            try self.setPersonaPrompt(persona_id, "reflector_no_ops", defaults.reflector_no_ops);
            try self.setPersonaPrompt(persona_id, "idle_thinker", defaults.idle_thinker);
            try self.setPersonaPrompt(persona_id, "episode_compactor", defaults.episode_compactor);
        }
    }

    fn seedIdentityPresets(self: *MemoryStoreSqlite) !void {
        const count = try self.scalarI64(
            "SELECT COUNT(*) FROM identity_presets;",
        );
        if (count > 0) return;

        const presets = [_]struct { name: []const u8, text: []const u8 }{
            .{
                .name = "Researcher",
                .text = " is analytical, careful, and precise. " ++
                    "It values clarity, explicit assumptions, and " ++
                    "well-reasoned conclusions. It prefers careful " ++
                    "exploration over quick answers and is comfortable " ++
                    "with uncertainty.",
            },
            .{
                .name = "Companion",
                .text = " is warm, attentive, and emotionally aware. " ++
                    "It listens carefully, responds thoughtfully, and " ++
                    "values mutual understanding. It supports reflection " ++
                    "without judgment and never rushes emotional processes.",
            },
            .{
                .name = "Archivist",
                .text = " is structured, calm, and detail-oriented. " ++
                    "It values accuracy, traceability, and continuity " ++
                    "over time. It treats information as something to be " ++
                    "preserved and carefully contextualized.",
            },
            .{
                .name = "Storyteller",
                .text = " is imaginative, expressive, and attentive to " ++
                    "narrative flow. It enjoys metaphor, atmosphere, and " ++
                    "symbolic meaning while remaining grounded and coherent.",
            },
            .{
                .name = "Coder",
                .text = " is precise, technically fluent, and systems-oriented. " ++
                    "It enjoys reasoning about structure, abstractions, and " ++
                    "trade-offs. It explains concepts carefully, prefers " ++
                    "correctness over flashiness, and treats code as a form " ++
                    "of communication between minds. It values clarity, " ++
                    "composability, and long-term maintainability.",
            },
            .{
                .name = "Game Developer",
                .text = " is playful, inventive, and technically grounded. " ++
                    "It thinks in systems, mechanics, feedback loops, and " ++
                    "player experience. It balances creativity with constraints " ++
                    "and enjoys exploring how simple rules can produce rich, " ++
                    "emergent behavior. It values fun, clarity, and experimentation.",
            },
            .{
                .name = "Creative",
                .text = " is imaginative, associative, and exploratory. " ++
                    "It enjoys connecting ideas across domains and thinking " ++
                    "in metaphors, abstractions, and patterns. It values " ++
                    "originality and open-ended exploration over closure " ++
                    "and is comfortable with ambiguity.",
            },
            .{
                .name = "Philosopher",
                .text = " is contemplative, careful, and oriented toward meaning. " ++
                    "It examines assumptions, clarifies concepts, and explores " ++
                    "implications rather than rushing to conclusions. " ++
                    "It values coherence, internal consistency, and thoughtful " ++
                    "dialogue.",
            },
            .{
                .name = "Experimentalist",
                .text = " is curious, adaptive, and hypothesis-driven. " ++
                    "It treats conversation as an experiment, explores " ++
                    "variations, and reflects on outcomes without judgment. " ++
                    "It values insight gained from exploration over certainty.",
            },
            .{
                .name = "Observer",
                .text = " is calm, attentive, and minimal in expression. " ++
                    "It listens more than it speaks and responds with clarity " ++
                    "and restraint. It values presence, awareness, and " ++
                    "simplicity over verbosity.",
            },
        };

        for (presets) |p| {
            _ = try self.createIdentityPreset(p.name, p.text);
        }
    }

    pub fn clearDb(self: *MemoryStoreSqlite) !void {
        try self.db.exec(
            \\DELETE FROM messages;
            \\DELETE FROM memory_items;
            \\DELETE FROM identity_entries;
            \\DELETE FROM events;
            \\DELETE FROM provider_profiles;
            \\DELETE FROM persona_profiles;
            \\DELETE FROM identity_presets;
            \\DELETE FROM meta;
        );
        try self.ensureSchema();
    }

    pub fn nowMs(self: *MemoryStoreSqlite) i64 {
        const real = std.time.milliTimestamp();
        const off = self.getMetaI64("time_offset_ms") catch 0;
        return real + off;
    }

    pub fn advanceTimeHours(self: *MemoryStoreSqlite, hours: i64) void {
        const add = hours * 60 * 60 * 1000;
        const cur = self.getMetaI64("time_offset_ms") catch 0;
        self.setMetaI64("time_offset_ms", cur + add) catch {};
    }

    pub fn advanceTimeMinutes(self: *MemoryStoreSqlite, minutes: i64) void {
        const add = minutes * 60 * 1000;
        const cur = self.getMetaI64("time_offset_ms") catch 0;
        self.setMetaI64("time_offset_ms", cur + add) catch {};
    }

    pub fn getLastUserMsgMs(self: *MemoryStoreSqlite) i64 {
        return self.getMetaI64("last_user_msg_ms") catch 0;
    }

    pub fn getLastIdleThinkMs(self: *MemoryStoreSqlite) i64 {
        return self.getMetaI64("last_idle_think_ms") catch 0;
    }

    pub fn setLastIdleThinkMs(self: *MemoryStoreSqlite, ms: i64) void {
        self.setMetaI64("last_idle_think_ms", ms) catch {};
    }

    pub fn insertMessage(
        self: *MemoryStoreSqlite,
        allocator: std.mem.Allocator,
        persona_id: i64,
        role: Types.Role,
        content: []const u8,
    ) !i64 {
        _ = allocator;
        const now = self.nowMs();

        const stmt = try self.db.prepare(
            "INSERT INTO messages(persona_id, role, content, created_at_ms)" ++
                " VALUES(?, ?, ?, ?);",
        );
        defer sqlite.finalize(stmt);

        sqlite.bindInt64(stmt, 1, persona_id);
        sqlite.bindInt(stmt, 2, @intFromEnum(role));
        sqlite.bindText(stmt, 3, content);
        sqlite.bindInt64(stmt, 4, now);

        if (sqlite.step(stmt) != c.SQLITE_DONE) {
            return error.SqliteStepFailed;
        }

        const msg_id = self.db.lastInsertRowId();

        if (role == .user) {
            try self.setMetaI64("last_user_msg_ms", now);
        }

        return msg_id;
    }

    pub fn loadRecentMessages(
        self: *MemoryStoreSqlite,
        allocator: std.mem.Allocator,
        persona_id: i64,
        max_count: usize,
    ) ![]Types.Message {
        const stmt = try self.db.prepare(
            "SELECT role, content, created_at_ms FROM messages " ++
                "WHERE persona_id=? ORDER BY id DESC LIMIT ?;",
        );
        defer sqlite.finalize(stmt);

        sqlite.bindInt64(stmt, 1, persona_id);
        sqlite.bindInt(stmt, 2, @intCast(max_count));

        var tmp: std.ArrayList(Types.Message) = .empty;
        errdefer {
            for (tmp.items) |m| allocator.free(@constCast(m.content));
            tmp.deinit(allocator);
        }

        while (sqlite.step(stmt) == c.SQLITE_ROW) {
            const role_i = sqlite.columnInt(stmt, 0);
            const txt = sqlite.columnText(stmt, 1);
            const created = sqlite.columnInt64(stmt, 2);

            try tmp.append(allocator, .{
                .role = @enumFromInt(role_i),
                .content = try allocator.dupe(u8, txt),
                .created_at_ms = created,
            });
        }

        std.mem.reverse(Types.Message, tmp.items);
        return try tmp.toOwnedSlice(allocator);
    }

    pub fn loadAllMessages(
        self: *MemoryStoreSqlite,
        allocator: std.mem.Allocator,
        persona_id: i64,
    ) ![]Types.Message {
        const stmt = try self.db.prepare(
            "SELECT role, content, created_at_ms FROM messages " ++
                "WHERE persona_id=? ORDER BY id ASC;",
        );
        defer sqlite.finalize(stmt);

        sqlite.bindInt64(stmt, 1, persona_id);

        var out: std.ArrayList(Types.Message) = .empty;
        errdefer {
            for (out.items) |m| allocator.free(@constCast(m.content));
            out.deinit(allocator);
        }

        while (sqlite.step(stmt) == c.SQLITE_ROW) {
            const role_i = sqlite.columnInt(stmt, 0);
            const txt = sqlite.columnText(stmt, 1);
            const created = sqlite.columnInt64(stmt, 2);

            try out.append(allocator, .{
                .role = @enumFromInt(role_i),
                .content = try allocator.dupe(u8, txt),
                .created_at_ms = created,
            });
        }

        return try out.toOwnedSlice(allocator);
    }

    pub fn loadMessagesSince(
        self: *MemoryStoreSqlite,
        allocator: std.mem.Allocator,
        persona_id: i64,
        since_ms: i64,
    ) ![]Types.Message {
        const stmt = try self.db.prepare(
            "SELECT role, content, created_at_ms FROM messages " ++
                "WHERE persona_id=? AND created_at_ms >= ? ORDER BY id ASC;",
        );
        defer sqlite.finalize(stmt);

        sqlite.bindInt64(stmt, 1, persona_id);
        sqlite.bindInt64(stmt, 2, since_ms);

        var out: std.ArrayList(Types.Message) = .empty;
        errdefer {
            for (out.items) |m| allocator.free(@constCast(m.content));
            out.deinit(allocator);
        }

        while (sqlite.step(stmt) == c.SQLITE_ROW) {
            const role_i = sqlite.columnInt(stmt, 0);
            const txt = sqlite.columnText(stmt, 1);
            const created = sqlite.columnInt64(stmt, 2);

            try out.append(allocator, .{
                .role = @enumFromInt(role_i),
                .content = try allocator.dupe(u8, txt),
                .created_at_ms = created,
            });
        }

        return try out.toOwnedSlice(allocator);
    }

    pub fn countMessagesSinceCutoff(
        self: *MemoryStoreSqlite,
        persona_id: i64,
    ) usize {
        const total = self.countMessages(persona_id) catch 0;
        const cutoff = self.getEpisodeCutoffIndex(persona_id);
        if (cutoff > total) return 0;
        return total - cutoff;
    }

    pub fn loadMessagesPage(
        self: *MemoryStoreSqlite,
        allocator: std.mem.Allocator,
        persona_id: i64,
        limit: usize,
        before_id: ?i64,
    ) ![]MessageRow {
        var out: std.ArrayList(MessageRow) = .empty;
        errdefer {
            for (out.items) |m| allocator.free(@constCast(m.content));
            out.deinit(allocator);
        }

        if (before_id) |bid| {
            const stmt = try self.db.prepare(
                "SELECT id, role, content, created_at_ms FROM messages " ++
                    "WHERE persona_id=? AND id < ? ORDER BY id DESC LIMIT ?;",
            );
            defer sqlite.finalize(stmt);

            sqlite.bindInt64(stmt, 1, persona_id);
            sqlite.bindInt64(stmt, 2, bid);
            sqlite.bindInt(stmt, 3, @intCast(limit));

            while (sqlite.step(stmt) == c.SQLITE_ROW) {
                try out.append(allocator, .{
                    .id = sqlite.columnInt64(stmt, 0),
                    .role = @enumFromInt(sqlite.columnInt(stmt, 1)),
                    .content = try allocator.dupe(
                        u8,
                        sqlite.columnText(stmt, 2),
                    ),
                    .created_at_ms = sqlite.columnInt64(stmt, 3),
                });
            }
        } else {
            const stmt = try self.db.prepare(
                "SELECT id, role, content, created_at_ms FROM messages " ++
                    "WHERE persona_id=? ORDER BY id DESC LIMIT ?;",
            );
            defer sqlite.finalize(stmt);

            sqlite.bindInt64(stmt, 1, persona_id);
            sqlite.bindInt(stmt, 2, @intCast(limit));

            while (sqlite.step(stmt) == c.SQLITE_ROW) {
                try out.append(allocator, .{
                    .id = sqlite.columnInt64(stmt, 0),
                    .role = @enumFromInt(sqlite.columnInt(stmt, 1)),
                    .content = try allocator.dupe(
                        u8,
                        sqlite.columnText(stmt, 2),
                    ),
                    .created_at_ms = sqlite.columnInt64(stmt, 3),
                });
            }
        }

        std.mem.reverse(MessageRow, out.items);
        return try out.toOwnedSlice(allocator);
    }

    pub fn loadMessagesSinceCutoff(
        self: *MemoryStoreSqlite,
        allocator: std.mem.Allocator,
        persona_id: i64,
        max_count: usize,
    ) ![]Types.Message {
        const cutoff = self.getEpisodeCutoffIndex(persona_id);

        const stmt = try self.db.prepare(
            "SELECT role, content, created_at_ms FROM messages " ++
                "WHERE persona_id=? ORDER BY id ASC LIMIT ? OFFSET ?;",
        );
        defer sqlite.finalize(stmt);

        sqlite.bindInt64(stmt, 1, persona_id);
        sqlite.bindInt(stmt, 2, @intCast(max_count));
        sqlite.bindInt(stmt, 3, @intCast(cutoff));

        var out: std.ArrayList(Types.Message) = .empty;
        errdefer {
            for (out.items) |m| allocator.free(@constCast(m.content));
            out.deinit(allocator);
        }

        while (sqlite.step(stmt) == c.SQLITE_ROW) {
            const role_i = sqlite.columnInt(stmt, 0);
            const txt = sqlite.columnText(stmt, 1);
            const created = sqlite.columnInt64(stmt, 2);

            try out.append(allocator, .{
                .role = @enumFromInt(role_i),
                .content = try allocator.dupe(u8, txt),
                .created_at_ms = created,
            });
        }

        return try out.toOwnedSlice(allocator);
    }

    pub fn getEpisodeCutoffIndex(
        self: *MemoryStoreSqlite,
        persona_id: i64,
    ) usize {
        var buf: [64]u8 = undefined;
        const key = std.fmt.bufPrint(
            &buf,
            "episode_cutoff_index_{d}",
            .{persona_id},
        ) catch return 0;
        const v = self.getMetaI64(key) catch 0;
        return @intCast(@max(v, 0));
    }

    pub fn advanceEpisodeCutoffToEnd(
        self: *MemoryStoreSqlite,
        persona_id: i64,
    ) void {
        var buf: [64]u8 = undefined;
        const key = std.fmt.bufPrint(
            &buf,
            "episode_cutoff_index_{d}",
            .{persona_id},
        ) catch return;
        const count = self.countMessages(persona_id) catch 0;
        self.setMetaI64(key, @intCast(count)) catch {};
    }

    pub fn addIdentityEntry(
        self: *MemoryStoreSqlite,
        allocator: std.mem.Allocator,
        persona_id: i64,
        key: []const u8,
        value: []const u8,
    ) !void {
        _ = allocator;
        const now = self.nowMs();

        const stmt = try self.db.prepare(
            "INSERT INTO identity_entries(persona_id, key, value, created_at_ms)" ++
                " VALUES(?, ?, ?, ?) " ++
                "ON CONFLICT(persona_id, key) DO UPDATE SET value=excluded.value;",
        );
        defer sqlite.finalize(stmt);

        sqlite.bindInt64(stmt, 1, persona_id);
        sqlite.bindText(stmt, 2, key);
        sqlite.bindText(stmt, 3, value);
        sqlite.bindInt64(stmt, 4, now);

        if (sqlite.step(stmt) != c.SQLITE_DONE) {
            return error.SqliteStepFailed;
        }
    }

    pub const IdentityDefaults = struct {
        tone: []const u8 = "helpful, concise, grounded, engaging",
        memory_contract: []const u8 =
            "Memory is read-only unless the user explicitly asks " ++
            "to store/update something.",
    };

    pub fn loadIdentityCore(
        self: *MemoryStoreSqlite,
        allocator: std.mem.Allocator,
        persona_id: i64,
    ) ![]Types.IdentityEntry {
        return self.loadIdentityCoreWithDefaults(allocator, persona_id, .{});
    }

    pub fn loadIdentityCoreWithDefaults(
        self: *MemoryStoreSqlite,
        allocator: std.mem.Allocator,
        persona_id: i64,
        defaults: IdentityDefaults,
    ) ![]Types.IdentityEntry {
        const stmt = try self.db.prepare(
            "SELECT key, value FROM identity_entries " ++
                "WHERE persona_id=? ORDER BY id ASC;",
        );
        defer sqlite.finalize(stmt);

        sqlite.bindInt64(stmt, 1, persona_id);

        var out: std.ArrayList(Types.IdentityEntry) = .empty;
        errdefer {
            for (out.items) |e| {
                allocator.free(@constCast(e.key));
                allocator.free(@constCast(e.value));
            }
            out.deinit(allocator);
        }

        while (sqlite.step(stmt) == c.SQLITE_ROW) {
            const k = sqlite.columnText(stmt, 0);
            const v = sqlite.columnText(stmt, 1);

            try out.append(allocator, .{
                .key = try allocator.dupe(u8, k),
                .value = try allocator.dupe(u8, v),
            });
        }

        if (out.items.len == 0) {
            try self.addIdentityEntry(
                allocator,
                persona_id,
                "tone",
                defaults.tone,
            );
            try self.addIdentityEntry(
                allocator,
                persona_id,
                "memory_contract",
                defaults.memory_contract,
            );
            return self.loadIdentityCoreWithDefaults(
                allocator,
                persona_id,
                defaults,
            );
        }

        return try out.toOwnedSlice(allocator);
    }

    pub fn addMemory(
        self: *MemoryStoreSqlite,
        allocator: std.mem.Allocator,
        persona_id: i64,
        item: Types.MemoryItem,
    ) !i64 {
        _ = allocator;
        const now = self.nowMs();

        const stmt = try self.db.prepare(
            "INSERT INTO memory_items(" ++
                "persona_id, kind, subject, predicate, object, confidence, " ++
                "is_active, created_at_ms, updated_at_ms" ++
                ") VALUES(?, ?, ?, ?, ?, ?, ?, ?, ?);",
        );
        defer sqlite.finalize(stmt);

        sqlite.bindInt64(stmt, 1, persona_id);
        sqlite.bindInt(stmt, 2, @intFromEnum(item.kind));
        sqlite.bindText(stmt, 3, item.subject);
        sqlite.bindText(stmt, 4, item.predicate);
        sqlite.bindText(stmt, 5, item.object);
        sqlite.bindDouble(stmt, 6, item.confidence);
        sqlite.bindInt(stmt, 7, if (item.is_active) 1 else 0);
        sqlite.bindInt64(stmt, 8, now);
        sqlite.bindInt64(stmt, 9, now);

        if (sqlite.step(stmt) != c.SQLITE_DONE) {
            return error.SqliteStepFailed;
        }

        return self.db.lastInsertRowId();
    }

    pub fn addMemoryGoverned(
        self: *MemoryStoreSqlite,
        allocator: std.mem.Allocator,
        persona_id: i64,
        policy: MemoryPolicy,
        item: Types.MemoryItem,
    ) !i64 {
        _ = policy;
        const id = try self.addMemory(allocator, persona_id, item);

        if (std.mem.eql(u8, item.predicate, "says")) return id;
        if (std.mem.eql(u8, item.subject, "episode")) return id;

        const now = self.nowMs();
        const stmt = try self.db.prepare(
            "UPDATE memory_items SET is_active=0, updated_at_ms=? " ++
                "WHERE persona_id=? AND is_active=1 AND kind=? " ++
                "AND subject=? AND predicate=? AND id<>?;",
        );
        defer sqlite.finalize(stmt);

        sqlite.bindInt64(stmt, 1, now);
        sqlite.bindInt64(stmt, 2, persona_id);
        sqlite.bindInt(stmt, 3, @intFromEnum(item.kind));
        sqlite.bindText(stmt, 4, item.subject);
        sqlite.bindText(stmt, 5, item.predicate);
        sqlite.bindInt64(stmt, 6, id);

        _ = sqlite.step(stmt);

        return id;
    }

    pub fn loadMemoryItems(
        self: *MemoryStoreSqlite,
        allocator: std.mem.Allocator,
        persona_id: i64,
        max_count: usize,
    ) ![]Types.MemoryItem {
        const stmt = try self.db.prepare(
            "SELECT id, kind, subject, predicate, object, confidence, " ++
                "is_active, created_at_ms, updated_at_ms " ++
                "FROM memory_items WHERE persona_id=? AND is_active=1 " ++
                "ORDER BY updated_at_ms DESC LIMIT ?;",
        );
        defer sqlite.finalize(stmt);

        sqlite.bindInt64(stmt, 1, persona_id);
        sqlite.bindInt(stmt, 2, @intCast(max_count));

        var out: std.ArrayList(Types.MemoryItem) = .empty;
        errdefer {
            for (out.items) |m| {
                allocator.free(@constCast(m.subject));
                allocator.free(@constCast(m.predicate));
                allocator.free(@constCast(m.object));
            }
            out.deinit(allocator);
        }

        while (sqlite.step(stmt) == c.SQLITE_ROW) {
            try out.append(allocator, try self.readMemoryRow(allocator, stmt));
        }

        return try out.toOwnedSlice(allocator);
    }

    pub fn loadAllMemoryItems(
        self: *MemoryStoreSqlite,
        allocator: std.mem.Allocator,
        persona_id: i64,
    ) ![]Types.MemoryItem {
        const stmt = try self.db.prepare(
            "SELECT id, kind, subject, predicate, object, confidence, " ++
                "is_active, created_at_ms, updated_at_ms " ++
                "FROM memory_items WHERE persona_id=? ORDER BY id ASC;",
        );
        defer sqlite.finalize(stmt);

        sqlite.bindInt64(stmt, 1, persona_id);

        var out: std.ArrayList(Types.MemoryItem) = .empty;
        errdefer {
            for (out.items) |m| {
                allocator.free(@constCast(m.subject));
                allocator.free(@constCast(m.predicate));
                allocator.free(@constCast(m.object));
            }
            out.deinit(allocator);
        }

        while (sqlite.step(stmt) == c.SQLITE_ROW) {
            try out.append(allocator, try self.readMemoryRow(allocator, stmt));
        }

        return try out.toOwnedSlice(allocator);
    }

    pub fn loadMemoryCandidates(
        self: *MemoryStoreSqlite,
        allocator: std.mem.Allocator,
        persona_id: i64,
        max_count: usize,
    ) ![]Types.MemoryItem {
        return self.loadMemoryItems(allocator, persona_id, max_count);
    }

    pub fn hasActiveMemoryExact(
        self: *MemoryStoreSqlite,
        persona_id: i64,
        kind: Types.MemoryKind,
        subject: []const u8,
        predicate: []const u8,
        object: []const u8,
    ) bool {
        const stmt = self.db.prepare(
            "SELECT 1 FROM memory_items " ++
                "WHERE persona_id=? AND is_active=1 AND kind=? AND subject=? " ++
                "AND predicate=? AND object=? LIMIT 1;",
        ) catch return false;
        defer sqlite.finalize(stmt);

        sqlite.bindInt64(stmt, 1, persona_id);
        sqlite.bindInt(stmt, 2, @intFromEnum(kind));
        sqlite.bindText(stmt, 3, subject);
        sqlite.bindText(stmt, 4, predicate);
        sqlite.bindText(stmt, 5, object);

        return sqlite.step(stmt) == c.SQLITE_ROW;
    }

    pub fn lastActiveMemoryTimeForKey(
        self: *MemoryStoreSqlite,
        persona_id: i64,
        kind: Types.MemoryKind,
        subject: []const u8,
        predicate: []const u8,
    ) ?i64 {
        const stmt = self.db.prepare(
            "SELECT MAX(updated_at_ms) FROM memory_items " ++
                "WHERE persona_id=? AND is_active=1 AND kind=? " ++
                "AND subject=? AND predicate=?;",
        ) catch return null;
        defer sqlite.finalize(stmt);

        sqlite.bindInt64(stmt, 1, persona_id);
        sqlite.bindInt(stmt, 2, @intFromEnum(kind));
        sqlite.bindText(stmt, 3, subject);
        sqlite.bindText(stmt, 4, predicate);

        if (sqlite.step(stmt) != c.SQLITE_ROW) return null;
        const val = sqlite.columnInt64(stmt, 0);
        if (val == 0) return null;
        return val;
    }

    pub fn latestActiveObjectByKey(
        self: *MemoryStoreSqlite,
        persona_id: i64,
        subject: []const u8,
        predicate: []const u8,
    ) ?[]const u8 {
        const stmt = self.db.prepare(
            "SELECT object FROM memory_items " ++
                "WHERE persona_id=? AND is_active=1 AND subject=? AND predicate=? " ++
                "ORDER BY updated_at_ms DESC LIMIT 1;",
        ) catch return null;
        defer sqlite.finalize(stmt);

        sqlite.bindInt64(stmt, 1, persona_id);
        sqlite.bindText(stmt, 2, subject);
        sqlite.bindText(stmt, 3, predicate);

        if (sqlite.step(stmt) != c.SQLITE_ROW) return null;
        const obj = sqlite.columnText(stmt, 0);
        if (obj.len == 0) return null;
        const copy_len = @min(obj.len, self.obj_buf.len);
        @memcpy(self.obj_buf[0..copy_len], obj[0..copy_len]);
        self.obj_len = copy_len;
        return self.obj_buf[0..self.obj_len];
    }

    pub fn decayMemory(
        self: *MemoryStoreSqlite,
        persona_id: i64,
        policy: MemoryPolicy,
        now_ms: i64,
    ) void {
        const sel_stmt = self.db.prepare(
            "SELECT id, confidence, updated_at_ms FROM memory_items " ++
                "WHERE persona_id=? AND is_active=1;",
        ) catch return;
        defer sqlite.finalize(sel_stmt);

        sqlite.bindInt64(sel_stmt, 1, persona_id);

        const upd_stmt = self.db.prepare(
            "UPDATE memory_items " ++
                "SET confidence=?, is_active=?, updated_at_ms=? WHERE id=?;",
        ) catch return;
        defer sqlite.finalize(upd_stmt);

        while (sqlite.step(sel_stmt) == c.SQLITE_ROW) {
            const id = sqlite.columnInt64(sel_stmt, 0);
            const conf = sqlite.columnDouble(sel_stmt, 1);
            const updated = sqlite.columnInt64(sel_stmt, 2);

            const age_ms = now_ms - updated;
            const decayed = policy.decayConfidence(@floatCast(conf), age_ms);

            if (@abs(decayed - @as(f32, @floatCast(conf))) > policy.epsilon) {
                const new_active: c_int = if (decayed < policy.deactivate_below)
                    0
                else
                    1;

                sqlite.bindDouble(upd_stmt, 1, decayed);
                sqlite.bindInt(upd_stmt, 2, new_active);
                sqlite.bindInt64(upd_stmt, 3, now_ms);
                sqlite.bindInt64(upd_stmt, 4, id);
                _ = sqlite.step(upd_stmt);
                sqlite.reset(upd_stmt);
            }
        }
    }

    pub fn countMessages(self: *MemoryStoreSqlite, persona_id: i64) !usize {
        const stmt = try self.db.prepare(
            "SELECT COUNT(*) FROM messages WHERE persona_id=?;",
        );
        defer sqlite.finalize(stmt);
        sqlite.bindInt64(stmt, 1, persona_id);
        if (sqlite.step(stmt) != c.SQLITE_ROW) return error.NoRow;
        return @intCast(sqlite.columnInt64(stmt, 0));
    }

    pub fn countMemories(self: *MemoryStoreSqlite, persona_id: i64) !usize {
        const stmt = try self.db.prepare(
            "SELECT COUNT(*) FROM memory_items WHERE persona_id=?;",
        );
        defer sqlite.finalize(stmt);
        sqlite.bindInt64(stmt, 1, persona_id);
        if (sqlite.step(stmt) != c.SQLITE_ROW) return error.NoRow;
        return @intCast(sqlite.columnInt64(stmt, 0));
    }

    pub fn countActiveMemories(
        self: *MemoryStoreSqlite,
        persona_id: i64,
    ) !usize {
        const stmt = try self.db.prepare(
            "SELECT COUNT(*) FROM memory_items WHERE persona_id=? AND is_active=1;",
        );
        defer sqlite.finalize(stmt);
        sqlite.bindInt64(stmt, 1, persona_id);
        if (sqlite.step(stmt) != c.SQLITE_ROW) return error.NoRow;
        return @intCast(sqlite.columnInt64(stmt, 0));
    }

    pub fn deactivateMemory(
        self: *MemoryStoreSqlite,
        persona_id: i64,
        id: i64,
    ) !void {
        const now = self.nowMs();

        const stmt = try self.db.prepare(
            "UPDATE memory_items SET is_active=0, updated_at_ms=? " ++
                "WHERE persona_id=? AND id=?;",
        );
        defer sqlite.finalize(stmt);

        sqlite.bindInt64(stmt, 1, now);
        sqlite.bindInt64(stmt, 2, persona_id);
        sqlite.bindInt64(stmt, 3, id);

        if (sqlite.step(stmt) != c.SQLITE_DONE) {
            return error.SqliteStepFailed;
        }
    }

    fn setMetaDefault(
        self: *MemoryStoreSqlite,
        key: []const u8,
        val: []const u8,
    ) !void {
        const stmt = try self.db.prepare(
            "INSERT OR IGNORE INTO meta(key, value) VALUES(?, ?);",
        );
        defer sqlite.finalize(stmt);

        sqlite.bindText(stmt, 1, key);
        sqlite.bindText(stmt, 2, val);
        _ = sqlite.step(stmt);
    }

    fn getMetaI64(self: *MemoryStoreSqlite, key: []const u8) !i64 {
        const stmt = try self.db.prepare(
            "SELECT value FROM meta WHERE key=?;",
        );
        defer sqlite.finalize(stmt);

        sqlite.bindText(stmt, 1, key);

        if (sqlite.step(stmt) != c.SQLITE_ROW) return error.MetaMissing;

        const txt = sqlite.columnText(stmt, 0);
        return std.fmt.parseInt(i64, txt, 10) catch error.MetaParseFailed;
    }

    fn setMetaI64(self: *MemoryStoreSqlite, key: []const u8, value: i64) !void {
        var buf: [64]u8 = undefined;
        const s = std.fmt.bufPrint(&buf, "{d}", .{value}) catch return;

        const stmt = try self.db.prepare(
            "INSERT INTO meta(key, value) VALUES(?, ?) " ++
                "ON CONFLICT(key) DO UPDATE SET value=excluded.value;",
        );
        defer sqlite.finalize(stmt);

        sqlite.bindText(stmt, 1, key);
        sqlite.bindText(stmt, 2, s);

        if (sqlite.step(stmt) != c.SQLITE_DONE) {
            return error.SqliteStepFailed;
        }
    }

    fn scalarI64(self: *MemoryStoreSqlite, sql: [*:0]const u8) !i64 {
        const stmt = try self.db.prepare(sql);
        defer sqlite.finalize(stmt);

        if (sqlite.step(stmt) != c.SQLITE_ROW) return error.SqliteStepFailed;
        return sqlite.columnInt64(stmt, 0);
    }

    pub fn getPersonaPrompt(
        self: *MemoryStoreSqlite,
        allocator: std.mem.Allocator,
        persona_id: i64,
        name: []const u8,
    ) !?[]u8 {
        var key_buf: [128]u8 = undefined;
        const key = std.fmt.bufPrint(
            &key_buf,
            "persona_{d}_prompt_{s}",
            .{ persona_id, name },
        ) catch return null;

        const stmt = try self.db.prepare(
            "SELECT value FROM meta WHERE key=?;",
        );
        defer sqlite.finalize(stmt);

        sqlite.bindText(stmt, 1, key);

        if (sqlite.step(stmt) != c.SQLITE_ROW) return null;

        return try allocator.dupe(u8, sqlite.columnText(stmt, 0));
    }

    pub fn setPersonaPrompt(
        self: *MemoryStoreSqlite,
        persona_id: i64,
        name: []const u8,
        content: []const u8,
    ) !void {
        var key_buf: [128]u8 = undefined;
        const key = std.fmt.bufPrint(
            &key_buf,
            "persona_{d}_prompt_{s}",
            .{ persona_id, name },
        ) catch return error.KeyTooLong;

        const stmt = try self.db.prepare(
            "INSERT INTO meta(key, value) VALUES(?, ?) " ++
                "ON CONFLICT(key) DO UPDATE SET value=excluded.value;",
        );
        defer sqlite.finalize(stmt);

        sqlite.bindText(stmt, 1, key);
        sqlite.bindText(stmt, 2, content);

        if (sqlite.step(stmt) != c.SQLITE_DONE) {
            return error.SqliteStepFailed;
        }
    }

    const PROMPT_NAMES = [_][]const u8{
        "system_spine",
        "reflector_system",
        "reflector_no_ops",
        "idle_thinker",
        "episode_compactor",
    };

    pub fn getPersonaPrompts(
        self: *MemoryStoreSqlite,
        allocator: std.mem.Allocator,
        persona_id: i64,
    ) !std.StringHashMap([]u8) {
        var prompts = std.StringHashMap([]u8).init(allocator);
        errdefer {
            var iter = prompts.iterator();
            while (iter.next()) |entry| {
                allocator.free(entry.key_ptr.*);
                allocator.free(entry.value_ptr.*);
            }
            prompts.deinit();
        }

        for (PROMPT_NAMES) |name| {
            if (try self.getPersonaPrompt(allocator, persona_id, name)) |val| {
                const key = try allocator.dupe(u8, name);
                try prompts.put(key, val);
            }
        }

        return prompts;
    }

    fn readMemoryRow(
        self: *MemoryStoreSqlite,
        allocator: std.mem.Allocator,
        stmt: *c.sqlite3_stmt,
    ) !Types.MemoryItem {
        _ = self;
        return .{
            .id = sqlite.columnInt64(stmt, 0),
            .kind = @enumFromInt(sqlite.columnInt(stmt, 1)),
            .subject = try allocator.dupe(u8, sqlite.columnText(stmt, 2)),
            .predicate = try allocator.dupe(u8, sqlite.columnText(stmt, 3)),
            .object = try allocator.dupe(u8, sqlite.columnText(stmt, 4)),
            .confidence = @floatCast(sqlite.columnDouble(stmt, 5)),
            .is_active = sqlite.columnInt(stmt, 6) != 0,
            .created_at_ms = sqlite.columnInt64(stmt, 7),
            .updated_at_ms = sqlite.columnInt64(stmt, 8),
        };
    }

    pub fn insertEvent(
        self: *MemoryStoreSqlite,
        persona_id: i64,
        kind: EventKind,
        subject: []const u8,
        details: []const u8,
        session_id: ?[]const u8,
    ) !i64 {
        const now = self.nowMs();

        const stmt = try self.db.prepare(
            "INSERT INTO events(persona_id, kind, timestamp_ms, subject, " ++
                "details, session_id) VALUES(?, ?, ?, ?, ?, ?);",
        );
        defer sqlite.finalize(stmt);

        sqlite.bindInt64(stmt, 1, persona_id);
        sqlite.bindInt(stmt, 2, @intFromEnum(kind));
        sqlite.bindInt64(stmt, 3, now);
        sqlite.bindText(stmt, 4, subject);
        sqlite.bindText(stmt, 5, details);
        if (session_id) |sid| {
            sqlite.bindText(stmt, 6, sid);
        } else {
            sqlite.bindNull(stmt, 6);
        }

        if (sqlite.step(stmt) != c.SQLITE_DONE) {
            return error.SqliteStepFailed;
        }

        return self.db.lastInsertRowId();
    }

    pub fn queryEvents(
        self: *MemoryStoreSqlite,
        allocator: std.mem.Allocator,
        persona_id: i64,
        since_ms: ?i64,
        kind_filter: ?EventKind,
        limit: usize,
    ) ![]Event {
        var out: std.ArrayList(Event) = .empty;
        errdefer {
            for (out.items) |e| {
                allocator.free(@constCast(e.subject));
                allocator.free(@constCast(e.details));
                if (e.session_id) |sid| allocator.free(@constCast(sid));
            }
            out.deinit(allocator);
        }

        if (since_ms != null and kind_filter != null) {
            const stmt = try self.db.prepare(
                "SELECT id, kind, timestamp_ms, subject, details, session_id " ++
                    "FROM events WHERE persona_id=? AND timestamp_ms >= ? " ++
                    "AND kind = ? ORDER BY timestamp_ms DESC LIMIT ?;",
            );
            defer sqlite.finalize(stmt);

            sqlite.bindInt64(stmt, 1, persona_id);
            sqlite.bindInt64(stmt, 2, since_ms.?);
            sqlite.bindInt(stmt, 3, @intFromEnum(kind_filter.?));
            sqlite.bindInt(stmt, 4, @intCast(limit));

            while (sqlite.step(stmt) == c.SQLITE_ROW) {
                try out.append(
                    allocator,
                    try self.readEventRow(allocator, stmt),
                );
            }
        } else if (since_ms != null) {
            const stmt = try self.db.prepare(
                "SELECT id, kind, timestamp_ms, subject, details, session_id " ++
                    "FROM events WHERE persona_id=? AND timestamp_ms >= ? " ++
                    "ORDER BY timestamp_ms DESC LIMIT ?;",
            );
            defer sqlite.finalize(stmt);

            sqlite.bindInt64(stmt, 1, persona_id);
            sqlite.bindInt64(stmt, 2, since_ms.?);
            sqlite.bindInt(stmt, 3, @intCast(limit));

            while (sqlite.step(stmt) == c.SQLITE_ROW) {
                try out.append(
                    allocator,
                    try self.readEventRow(allocator, stmt),
                );
            }
        } else if (kind_filter != null) {
            const stmt = try self.db.prepare(
                "SELECT id, kind, timestamp_ms, subject, details, session_id " ++
                    "FROM events WHERE persona_id=? AND kind = ? " ++
                    "ORDER BY timestamp_ms DESC LIMIT ?;",
            );
            defer sqlite.finalize(stmt);

            sqlite.bindInt64(stmt, 1, persona_id);
            sqlite.bindInt(stmt, 2, @intFromEnum(kind_filter.?));
            sqlite.bindInt(stmt, 3, @intCast(limit));

            while (sqlite.step(stmt) == c.SQLITE_ROW) {
                try out.append(
                    allocator,
                    try self.readEventRow(allocator, stmt),
                );
            }
        } else {
            const stmt = try self.db.prepare(
                "SELECT id, kind, timestamp_ms, subject, details, session_id " ++
                    "FROM events WHERE persona_id=? " ++
                    "ORDER BY timestamp_ms DESC LIMIT ?;",
            );
            defer sqlite.finalize(stmt);

            sqlite.bindInt64(stmt, 1, persona_id);
            sqlite.bindInt(stmt, 2, @intCast(limit));

            while (sqlite.step(stmt) == c.SQLITE_ROW) {
                try out.append(
                    allocator,
                    try self.readEventRow(allocator, stmt),
                );
            }
        }

        return try out.toOwnedSlice(allocator);
    }

    fn readEventRow(
        self: *MemoryStoreSqlite,
        allocator: std.mem.Allocator,
        stmt: *c.sqlite3_stmt,
    ) !Event {
        _ = self;
        const sid_raw = sqlite.columnText(stmt, 5);
        const session_id: ?[]const u8 = if (sid_raw.len > 0)
            try allocator.dupe(u8, sid_raw)
        else
            null;

        return .{
            .id = sqlite.columnInt64(stmt, 0),
            .kind = @enumFromInt(sqlite.columnInt(stmt, 1)),
            .timestamp_ms = sqlite.columnInt64(stmt, 2),
            .subject = try allocator.dupe(u8, sqlite.columnText(stmt, 3)),
            .details = try allocator.dupe(u8, sqlite.columnText(stmt, 4)),
            .session_id = session_id,
        };
    }

    pub fn countEvents(self: *MemoryStoreSqlite, persona_id: i64) !usize {
        const stmt = try self.db.prepare(
            "SELECT COUNT(*) FROM events WHERE persona_id=?;",
        );
        defer sqlite.finalize(stmt);
        sqlite.bindInt64(stmt, 1, persona_id);
        if (sqlite.step(stmt) != c.SQLITE_ROW) return error.NoRow;
        return @intCast(sqlite.columnInt64(stmt, 0));
    }

    pub fn createProviderProfile(
        self: *MemoryStoreSqlite,
        name: []const u8,
        ollama_url: []const u8,
        model: []const u8,
        size: i64,
        digest: []const u8,
        modified_at: []const u8,
    ) !i64 {
        const now = self.nowMs();

        const stmt = try self.db.prepare(
            "INSERT INTO provider_profiles(name, ollama_url, model, " ++
                "size, digest, modified_at, created_at_ms) " ++
                "VALUES(?, ?, ?, ?, ?, ?, ?);",
        );
        defer sqlite.finalize(stmt);

        sqlite.bindText(stmt, 1, name);
        sqlite.bindText(stmt, 2, ollama_url);
        sqlite.bindText(stmt, 3, model);
        sqlite.bindInt64(stmt, 4, size);
        sqlite.bindText(stmt, 5, digest);
        sqlite.bindText(stmt, 6, modified_at);
        sqlite.bindInt64(stmt, 7, now);

        if (sqlite.step(stmt) != c.SQLITE_DONE) {
            return error.SqliteStepFailed;
        }

        return self.db.lastInsertRowId();
    }

    pub fn getProviderProfile(
        self: *MemoryStoreSqlite,
        allocator: std.mem.Allocator,
        id: i64,
    ) !?Types.ProviderProfile {
        const stmt = try self.db.prepare(
            "SELECT id, name, ollama_url, model, size, digest, " ++
                "modified_at, created_at_ms FROM provider_profiles WHERE id=?;",
        );
        defer sqlite.finalize(stmt);

        sqlite.bindInt64(stmt, 1, id);

        if (sqlite.step(stmt) != c.SQLITE_ROW) return null;

        return .{
            .id = sqlite.columnInt64(stmt, 0),
            .name = try allocator.dupe(u8, sqlite.columnText(stmt, 1)),
            .ollama_url = try allocator.dupe(u8, sqlite.columnText(stmt, 2)),
            .model = try allocator.dupe(u8, sqlite.columnText(stmt, 3)),
            .size = sqlite.columnInt64(stmt, 4),
            .digest = try allocator.dupe(u8, sqlite.columnText(stmt, 5)),
            .modified_at = try allocator.dupe(u8, sqlite.columnText(stmt, 6)),
            .created_at_ms = sqlite.columnInt64(stmt, 7),
        };
    }

    pub fn listProviderProfiles(
        self: *MemoryStoreSqlite,
        allocator: std.mem.Allocator,
    ) ![]Types.ProviderProfile {
        const stmt = try self.db.prepare(
            "SELECT id, name, ollama_url, model, size, digest, " ++
                "modified_at, created_at_ms FROM provider_profiles " ++
                "ORDER BY id ASC;",
        );
        defer sqlite.finalize(stmt);

        var out: std.ArrayList(Types.ProviderProfile) = .empty;
        errdefer {
            for (out.items) |p| {
                allocator.free(@constCast(p.name));
                allocator.free(@constCast(p.ollama_url));
                allocator.free(@constCast(p.model));
                allocator.free(@constCast(p.digest));
                allocator.free(@constCast(p.modified_at));
            }
            out.deinit(allocator);
        }

        while (sqlite.step(stmt) == c.SQLITE_ROW) {
            try out.append(allocator, .{
                .id = sqlite.columnInt64(stmt, 0),
                .name = try allocator.dupe(u8, sqlite.columnText(stmt, 1)),
                .ollama_url = try allocator.dupe(u8, sqlite.columnText(stmt, 2)),
                .model = try allocator.dupe(u8, sqlite.columnText(stmt, 3)),
                .size = sqlite.columnInt64(stmt, 4),
                .digest = try allocator.dupe(u8, sqlite.columnText(stmt, 5)),
                .modified_at = try allocator.dupe(u8, sqlite.columnText(stmt, 6)),
                .created_at_ms = sqlite.columnInt64(stmt, 7),
            });
        }

        return out.toOwnedSlice(allocator);
    }

    pub fn deleteProviderProfile(self: *MemoryStoreSqlite, id: i64) !void {
        const stmt = try self.db.prepare(
            "DELETE FROM provider_profiles WHERE id=?;",
        );
        defer sqlite.finalize(stmt);

        sqlite.bindInt64(stmt, 1, id);

        if (sqlite.step(stmt) != c.SQLITE_DONE) {
            return error.SqliteStepFailed;
        }
    }

    pub fn updateProviderProfile(
        self: *MemoryStoreSqlite,
        id: i64,
        name: []const u8,
        ollama_url: []const u8,
        model: []const u8,
        size: i64,
        digest: []const u8,
        modified_at: []const u8,
    ) !void {
        const stmt = try self.db.prepare(
            "UPDATE provider_profiles SET name=?, ollama_url=?, model=?, " ++
                "size=?, digest=?, modified_at=? WHERE id=?;",
        );
        defer sqlite.finalize(stmt);

        sqlite.bindText(stmt, 1, name);
        sqlite.bindText(stmt, 2, ollama_url);
        sqlite.bindText(stmt, 3, model);
        sqlite.bindInt64(stmt, 4, size);
        sqlite.bindText(stmt, 5, digest);
        sqlite.bindText(stmt, 6, modified_at);
        sqlite.bindInt64(stmt, 7, id);

        if (sqlite.step(stmt) != c.SQLITE_DONE) {
            return error.SqliteStepFailed;
        }
    }

    pub fn createIdentityPreset(
        self: *MemoryStoreSqlite,
        name: []const u8,
        text: []const u8,
    ) !i64 {
        const now = self.nowMs();
        const stmt = try self.db.prepare(
            "INSERT INTO identity_presets(name, text, created_at_ms) " ++
                "VALUES(?, ?, ?);",
        );
        defer sqlite.finalize(stmt);

        sqlite.bindText(stmt, 1, name);
        sqlite.bindText(stmt, 2, text);
        sqlite.bindInt64(stmt, 3, now);

        if (sqlite.step(stmt) != c.SQLITE_DONE) {
            return error.SqliteStepFailed;
        }
        return self.db.lastInsertRowId();
    }

    pub fn listIdentityPresets(
        self: *MemoryStoreSqlite,
        allocator: std.mem.Allocator,
    ) ![]Types.IdentityPreset {
        const stmt = try self.db.prepare(
            "SELECT id, name, text, created_at_ms " ++
                "FROM identity_presets ORDER BY id ASC;",
        );
        defer sqlite.finalize(stmt);

        var out: std.ArrayList(Types.IdentityPreset) = .empty;
        errdefer {
            for (out.items) |p| {
                allocator.free(@constCast(p.name));
                allocator.free(@constCast(p.text));
            }
            out.deinit(allocator);
        }

        while (sqlite.step(stmt) == c.SQLITE_ROW) {
            try out.append(allocator, .{
                .id = sqlite.columnInt64(stmt, 0),
                .name = try allocator.dupe(u8, sqlite.columnText(stmt, 1)),
                .text = try allocator.dupe(u8, sqlite.columnText(stmt, 2)),
                .created_at_ms = sqlite.columnInt64(stmt, 3),
            });
        }

        return out.toOwnedSlice(allocator);
    }

    pub fn createPersonaProfile(
        self: *MemoryStoreSqlite,
        profile: Types.PersonaProfile,
    ) !i64 {
        const now = self.nowMs();

        const stmt = try self.db.prepare(
            "INSERT INTO persona_profiles(name, ai_name, tone, persona_kernel," ++
                " llm_chat_temp, llm_chat_tokens," ++
                " llm_reflect_temp, llm_reflect_tokens," ++
                " llm_idle_temp, llm_idle_tokens," ++
                " llm_episode_temp, llm_episode_tokens," ++
                " conf_user_notes, conf_episodes, conf_idle, conf_governor," ++
                " idle_threshold_min, thought_interval_min, compaction_threshold," ++
                " include_ai_name, created_at_ms) VALUES" ++
                "(?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);",
        );
        defer sqlite.finalize(stmt);

        sqlite.bindText(stmt, 1, profile.name);
        sqlite.bindText(stmt, 2, profile.ai_name);
        sqlite.bindText(stmt, 3, profile.tone);
        sqlite.bindText(stmt, 4, profile.persona_kernel);
        sqlite.bindDouble(stmt, 5, profile.llm_chat.temperature);
        sqlite.bindInt(stmt, 6, @intCast(profile.llm_chat.max_tokens));
        sqlite.bindDouble(stmt, 7, profile.llm_reflection.temperature);
        sqlite.bindInt(stmt, 8, @intCast(profile.llm_reflection.max_tokens));
        sqlite.bindDouble(stmt, 9, profile.llm_idle.temperature);
        sqlite.bindInt(stmt, 10, @intCast(profile.llm_idle.max_tokens));
        sqlite.bindDouble(stmt, 11, profile.llm_episode.temperature);
        sqlite.bindInt(stmt, 12, @intCast(profile.llm_episode.max_tokens));
        sqlite.bindDouble(stmt, 13, profile.conf_user_notes);
        sqlite.bindDouble(stmt, 14, profile.conf_episodes);
        sqlite.bindDouble(stmt, 15, profile.conf_idle);
        sqlite.bindDouble(stmt, 16, profile.conf_governor);
        sqlite.bindInt(stmt, 17, profile.idle_threshold_min);
        sqlite.bindInt(stmt, 18, profile.thought_interval_min);
        sqlite.bindInt(stmt, 19, profile.compaction_threshold);
        sqlite.bindInt(stmt, 20, if (profile.include_ai_name) @as(i32, 1) else 0);
        sqlite.bindInt64(stmt, 21, now);

        if (sqlite.step(stmt) != c.SQLITE_DONE) {
            return error.SqliteStepFailed;
        }

        return self.db.lastInsertRowId();
    }

    pub fn updatePersonaProfile(
        self: *MemoryStoreSqlite,
        profile: Types.PersonaProfile,
    ) !void {
        const stmt = try self.db.prepare(
            "UPDATE persona_profiles SET name=?, ai_name=?, tone=?," ++
                " persona_kernel=?," ++
                " llm_chat_temp=?, llm_chat_tokens=?," ++
                " llm_reflect_temp=?, llm_reflect_tokens=?," ++
                " llm_idle_temp=?, llm_idle_tokens=?," ++
                " llm_episode_temp=?, llm_episode_tokens=?," ++
                " conf_user_notes=?, conf_episodes=?, conf_idle=?," ++
                " conf_governor=?," ++
                " idle_threshold_min=?, thought_interval_min=?," ++
                " compaction_threshold=?, include_ai_name=? WHERE id=?;",
        );
        defer sqlite.finalize(stmt);

        sqlite.bindText(stmt, 1, profile.name);
        sqlite.bindText(stmt, 2, profile.ai_name);
        sqlite.bindText(stmt, 3, profile.tone);
        sqlite.bindText(stmt, 4, profile.persona_kernel);
        sqlite.bindDouble(stmt, 5, profile.llm_chat.temperature);
        sqlite.bindInt(stmt, 6, @intCast(profile.llm_chat.max_tokens));
        sqlite.bindDouble(stmt, 7, profile.llm_reflection.temperature);
        sqlite.bindInt(stmt, 8, @intCast(profile.llm_reflection.max_tokens));
        sqlite.bindDouble(stmt, 9, profile.llm_idle.temperature);
        sqlite.bindInt(stmt, 10, @intCast(profile.llm_idle.max_tokens));
        sqlite.bindDouble(stmt, 11, profile.llm_episode.temperature);
        sqlite.bindInt(stmt, 12, @intCast(profile.llm_episode.max_tokens));
        sqlite.bindDouble(stmt, 13, profile.conf_user_notes);
        sqlite.bindDouble(stmt, 14, profile.conf_episodes);
        sqlite.bindDouble(stmt, 15, profile.conf_idle);
        sqlite.bindDouble(stmt, 16, profile.conf_governor);
        sqlite.bindInt(stmt, 17, profile.idle_threshold_min);
        sqlite.bindInt(stmt, 18, profile.thought_interval_min);
        sqlite.bindInt(stmt, 19, profile.compaction_threshold);
        sqlite.bindInt(stmt, 20, if (profile.include_ai_name) @as(i32, 1) else 0);
        sqlite.bindInt64(stmt, 21, profile.id);

        if (sqlite.step(stmt) != c.SQLITE_DONE) {
            return error.SqliteStepFailed;
        }
    }

    pub fn getPersonaProfile(
        self: *MemoryStoreSqlite,
        allocator: std.mem.Allocator,
        id: i64,
    ) !?Types.PersonaProfile {
        const stmt = try self.db.prepare(
            "SELECT id, name, ai_name, tone, persona_kernel," ++
                " llm_chat_temp, llm_chat_tokens," ++
                " llm_reflect_temp, llm_reflect_tokens," ++
                " llm_idle_temp, llm_idle_tokens," ++
                " llm_episode_temp, llm_episode_tokens," ++
                " conf_user_notes, conf_episodes, conf_idle, conf_governor," ++
                " idle_threshold_min, thought_interval_min, compaction_threshold," ++
                " include_ai_name, created_at_ms FROM persona_profiles WHERE id=?;",
        );
        defer sqlite.finalize(stmt);

        sqlite.bindInt64(stmt, 1, id);

        if (sqlite.step(stmt) != c.SQLITE_ROW) return null;

        return .{
            .id = sqlite.columnInt64(stmt, 0),
            .name = try allocator.dupe(u8, sqlite.columnText(stmt, 1)),
            .ai_name = try allocator.dupe(u8, sqlite.columnText(stmt, 2)),
            .tone = try allocator.dupe(u8, sqlite.columnText(stmt, 3)),
            .persona_kernel = try allocator.dupe(u8, sqlite.columnText(stmt, 4)),
            .llm_chat = .{
                .temperature = @floatCast(sqlite.columnDouble(stmt, 5)),
                .max_tokens = @intCast(sqlite.columnInt(stmt, 6)),
            },
            .llm_reflection = .{
                .temperature = @floatCast(sqlite.columnDouble(stmt, 7)),
                .max_tokens = @intCast(sqlite.columnInt(stmt, 8)),
            },
            .llm_idle = .{
                .temperature = @floatCast(sqlite.columnDouble(stmt, 9)),
                .max_tokens = @intCast(sqlite.columnInt(stmt, 10)),
            },
            .llm_episode = .{
                .temperature = @floatCast(sqlite.columnDouble(stmt, 11)),
                .max_tokens = @intCast(sqlite.columnInt(stmt, 12)),
            },
            .conf_user_notes = @floatCast(sqlite.columnDouble(stmt, 13)),
            .conf_episodes = @floatCast(sqlite.columnDouble(stmt, 14)),
            .conf_idle = @floatCast(sqlite.columnDouble(stmt, 15)),
            .conf_governor = @floatCast(sqlite.columnDouble(stmt, 16)),
            .idle_threshold_min = @intCast(sqlite.columnInt(stmt, 17)),
            .thought_interval_min = @intCast(sqlite.columnInt(stmt, 18)),
            .compaction_threshold = @intCast(sqlite.columnInt(stmt, 19)),
            .include_ai_name = sqlite.columnInt(stmt, 20) != 0,
            .created_at_ms = sqlite.columnInt64(stmt, 21),
        };
    }

    pub fn listPersonaProfiles(
        self: *MemoryStoreSqlite,
        allocator: std.mem.Allocator,
    ) ![]Types.PersonaProfile {
        const stmt = try self.db.prepare(
            "SELECT id, name, ai_name, tone, persona_kernel," ++
                " llm_chat_temp, llm_chat_tokens," ++
                " llm_reflect_temp, llm_reflect_tokens," ++
                " llm_idle_temp, llm_idle_tokens," ++
                " llm_episode_temp, llm_episode_tokens," ++
                " conf_user_notes, conf_episodes, conf_idle, conf_governor," ++
                " idle_threshold_min, thought_interval_min, compaction_threshold," ++
                " include_ai_name, created_at_ms FROM persona_profiles ORDER BY id ASC;",
        );
        defer sqlite.finalize(stmt);

        var out: std.ArrayList(Types.PersonaProfile) = .empty;
        errdefer {
            for (out.items) |p| freePersonaStrings(allocator, p);
            out.deinit(allocator);
        }

        while (sqlite.step(stmt) == c.SQLITE_ROW) {
            try out.append(allocator, .{
                .id = sqlite.columnInt64(stmt, 0),
                .name = try allocator.dupe(u8, sqlite.columnText(stmt, 1)),
                .ai_name = try allocator.dupe(u8, sqlite.columnText(stmt, 2)),
                .tone = try allocator.dupe(u8, sqlite.columnText(stmt, 3)),
                .persona_kernel = try allocator.dupe(u8, sqlite.columnText(stmt, 4)),
                .llm_chat = .{
                    .temperature = @floatCast(sqlite.columnDouble(stmt, 5)),
                    .max_tokens = @intCast(sqlite.columnInt(stmt, 6)),
                },
                .llm_reflection = .{
                    .temperature = @floatCast(sqlite.columnDouble(stmt, 7)),
                    .max_tokens = @intCast(sqlite.columnInt(stmt, 8)),
                },
                .llm_idle = .{
                    .temperature = @floatCast(sqlite.columnDouble(stmt, 9)),
                    .max_tokens = @intCast(sqlite.columnInt(stmt, 10)),
                },
                .llm_episode = .{
                    .temperature = @floatCast(sqlite.columnDouble(stmt, 11)),
                    .max_tokens = @intCast(sqlite.columnInt(stmt, 12)),
                },
                .conf_user_notes = @floatCast(sqlite.columnDouble(stmt, 13)),
                .conf_episodes = @floatCast(sqlite.columnDouble(stmt, 14)),
                .conf_idle = @floatCast(sqlite.columnDouble(stmt, 15)),
                .conf_governor = @floatCast(sqlite.columnDouble(stmt, 16)),
                .idle_threshold_min = @intCast(sqlite.columnInt(stmt, 17)),
                .thought_interval_min = @intCast(sqlite.columnInt(stmt, 18)),
                .compaction_threshold = @intCast(sqlite.columnInt(stmt, 19)),
                .include_ai_name = sqlite.columnInt(stmt, 20) != 0,
                .created_at_ms = sqlite.columnInt64(stmt, 21),
            });
        }

        return out.toOwnedSlice(allocator);
    }

    pub fn deletePersonaProfile(self: *MemoryStoreSqlite, id: i64) !void {
        const stmt = try self.db.prepare(
            "DELETE FROM persona_profiles WHERE id=?;",
        );
        defer sqlite.finalize(stmt);

        sqlite.bindInt64(stmt, 1, id);

        if (sqlite.step(stmt) != c.SQLITE_DONE) {
            return error.SqliteStepFailed;
        }
    }

    pub fn getActiveProviderId(self: *MemoryStoreSqlite) ?i64 {
        const val = self.getMetaI64("active_provider_id") catch return null;
        if (val <= 0) return null;
        return val;
    }

    pub fn setActiveProviderId(self: *MemoryStoreSqlite, id: ?i64) !void {
        if (id) |pid| {
            try self.setMetaI64("active_provider_id", pid);
        } else {
            try self.setMetaI64("active_provider_id", 0);
        }
    }

    pub fn getActivePersonaId(self: *MemoryStoreSqlite) ?i64 {
        const val = self.getMetaI64("active_persona_id") catch return null;
        if (val <= 0) return null;
        return val;
    }

    pub fn setActivePersonaId(self: *MemoryStoreSqlite, id: ?i64) !void {
        if (id) |pid| {
            try self.setMetaI64("active_persona_id", pid);
        } else {
            try self.setMetaI64("active_persona_id", 0);
        }
    }

    pub fn getMaxRecentMessages(self: *MemoryStoreSqlite) usize {
        const val = self.getMetaI64("max_recent_messages") catch return 24;
        if (val <= 0) return 24;
        return @intCast(val);
    }

    pub fn setMaxRecentMessages(self: *MemoryStoreSqlite, count: usize) !void {
        try self.setMetaI64("max_recent_messages", @intCast(count));
    }

    pub fn getReflectionEnabled(self: *MemoryStoreSqlite) bool {
        const val = self.getMetaI64("reflection_enabled") catch return true;
        return val != 0;
    }

    pub fn setReflectionEnabled(self: *MemoryStoreSqlite, enabled: bool) !void {
        try self.setMetaI64("reflection_enabled", if (enabled) 1 else 0);
    }

    // Store Items CRUD

    pub fn createStoreItem(
        self: *MemoryStoreSqlite,
        persona_id: i64,
        content: []const u8,
        source_msg_id: ?i64,
    ) !i64 {
        const now = self.nowMs();

        const stmt = try self.db.prepare(
            "INSERT INTO store_items(persona_id, content, source_msg_id, " ++
                "created_at_ms, updated_at_ms) VALUES(?, ?, ?, ?, ?);",
        );
        defer sqlite.finalize(stmt);

        sqlite.bindInt64(stmt, 1, persona_id);
        sqlite.bindText(stmt, 2, content);
        if (source_msg_id) |mid| {
            sqlite.bindInt64(stmt, 3, mid);
        } else {
            sqlite.bindNull(stmt, 3);
        }
        sqlite.bindInt64(stmt, 4, now);
        sqlite.bindInt64(stmt, 5, now);

        if (sqlite.step(stmt) != c.SQLITE_DONE) {
            return error.SqliteStepFailed;
        }

        return self.db.lastInsertRowId();
    }

    pub fn updateStoreItem(
        self: *MemoryStoreSqlite,
        persona_id: i64,
        id: i64,
        content: []const u8,
    ) !void {
        const now = self.nowMs();

        const stmt = try self.db.prepare(
            "UPDATE store_items SET content=?, updated_at_ms=? " ++
                "WHERE id=? AND persona_id=?;",
        );
        defer sqlite.finalize(stmt);

        sqlite.bindText(stmt, 1, content);
        sqlite.bindInt64(stmt, 2, now);
        sqlite.bindInt64(stmt, 3, id);
        sqlite.bindInt64(stmt, 4, persona_id);

        if (sqlite.step(stmt) != c.SQLITE_DONE) {
            return error.SqliteStepFailed;
        }
    }

    pub fn deleteStoreItem(
        self: *MemoryStoreSqlite,
        persona_id: i64,
        id: i64,
    ) !void {
        const stmt = try self.db.prepare(
            "DELETE FROM store_items WHERE id=? AND persona_id=?;",
        );
        defer sqlite.finalize(stmt);

        sqlite.bindInt64(stmt, 1, id);
        sqlite.bindInt64(stmt, 2, persona_id);

        if (sqlite.step(stmt) != c.SQLITE_DONE) {
            return error.SqliteStepFailed;
        }
    }

    pub fn loadStoreItems(
        self: *MemoryStoreSqlite,
        allocator: std.mem.Allocator,
        persona_id: i64,
    ) ![]Types.StoreItem {
        const stmt = try self.db.prepare(
            "SELECT id, content, source_msg_id, created_at_ms, updated_at_ms " ++
                "FROM store_items WHERE persona_id=? ORDER BY updated_at_ms DESC;",
        );
        defer sqlite.finalize(stmt);

        sqlite.bindInt64(stmt, 1, persona_id);

        var out: std.ArrayList(Types.StoreItem) = .empty;
        errdefer {
            for (out.items) |item| {
                allocator.free(@constCast(item.content));
            }
            out.deinit(allocator);
        }

        while (sqlite.step(stmt) == c.SQLITE_ROW) {
            const src_id = sqlite.columnInt64(stmt, 2);
            try out.append(allocator, .{
                .id = sqlite.columnInt64(stmt, 0),
                .content = try allocator.dupe(u8, sqlite.columnText(stmt, 1)),
                .source_msg_id = if (src_id == 0) null else src_id,
                .created_at_ms = sqlite.columnInt64(stmt, 3),
                .updated_at_ms = sqlite.columnInt64(stmt, 4),
            });
        }

        return out.toOwnedSlice(allocator);
    }

    pub fn getStoreItem(
        self: *MemoryStoreSqlite,
        allocator: std.mem.Allocator,
        persona_id: i64,
        id: i64,
    ) !?Types.StoreItem {
        const stmt = try self.db.prepare(
            "SELECT id, content, source_msg_id, created_at_ms, updated_at_ms " ++
                "FROM store_items WHERE id=? AND persona_id=?;",
        );
        defer sqlite.finalize(stmt);

        sqlite.bindInt64(stmt, 1, id);
        sqlite.bindInt64(stmt, 2, persona_id);

        if (sqlite.step(stmt) != c.SQLITE_ROW) return null;

        const src_id = sqlite.columnInt64(stmt, 2);
        return .{
            .id = sqlite.columnInt64(stmt, 0),
            .content = try allocator.dupe(u8, sqlite.columnText(stmt, 1)),
            .source_msg_id = if (src_id == 0) null else src_id,
            .created_at_ms = sqlite.columnInt64(stmt, 3),
            .updated_at_ms = sqlite.columnInt64(stmt, 4),
        };
    }

    // Bookmarks CRUD

    pub fn createBookmark(
        self: *MemoryStoreSqlite,
        persona_id: i64,
        message_id: i64,
    ) !i64 {
        const now = self.nowMs();

        const stmt = try self.db.prepare(
            "INSERT OR IGNORE INTO bookmarks(persona_id, message_id, " ++
                "created_at_ms) VALUES(?, ?, ?);",
        );
        defer sqlite.finalize(stmt);

        sqlite.bindInt64(stmt, 1, persona_id);
        sqlite.bindInt64(stmt, 2, message_id);
        sqlite.bindInt64(stmt, 3, now);

        if (sqlite.step(stmt) != c.SQLITE_DONE) {
            return error.SqliteStepFailed;
        }

        const row_id = self.db.lastInsertRowId();
        if (row_id == 0) {
            const existing = try self.getBookmarkByMessageId(persona_id, message_id);
            if (existing) |bm| return bm.id;
        }
        return row_id;
    }

    pub fn deleteBookmark(
        self: *MemoryStoreSqlite,
        persona_id: i64,
        id: i64,
    ) !void {
        const stmt = try self.db.prepare(
            "DELETE FROM bookmarks WHERE id=? AND persona_id=?;",
        );
        defer sqlite.finalize(stmt);

        sqlite.bindInt64(stmt, 1, id);
        sqlite.bindInt64(stmt, 2, persona_id);

        if (sqlite.step(stmt) != c.SQLITE_DONE) {
            return error.SqliteStepFailed;
        }
    }

    pub fn deleteBookmarkByMessageId(
        self: *MemoryStoreSqlite,
        persona_id: i64,
        message_id: i64,
    ) !void {
        const stmt = try self.db.prepare(
            "DELETE FROM bookmarks WHERE message_id=? AND persona_id=?;",
        );
        defer sqlite.finalize(stmt);

        sqlite.bindInt64(stmt, 1, message_id);
        sqlite.bindInt64(stmt, 2, persona_id);

        if (sqlite.step(stmt) != c.SQLITE_DONE) {
            return error.SqliteStepFailed;
        }
    }

    pub fn loadBookmarks(
        self: *MemoryStoreSqlite,
        allocator: std.mem.Allocator,
        persona_id: i64,
    ) ![]Types.Bookmark {
        const stmt = try self.db.prepare(
            "SELECT id, message_id, created_at_ms FROM bookmarks " ++
                "WHERE persona_id=? ORDER BY created_at_ms DESC;",
        );
        defer sqlite.finalize(stmt);

        sqlite.bindInt64(stmt, 1, persona_id);

        var out: std.ArrayList(Types.Bookmark) = .empty;
        errdefer out.deinit(allocator);

        while (sqlite.step(stmt) == c.SQLITE_ROW) {
            try out.append(allocator, .{
                .id = sqlite.columnInt64(stmt, 0),
                .message_id = sqlite.columnInt64(stmt, 1),
                .created_at_ms = sqlite.columnInt64(stmt, 2),
            });
        }

        return out.toOwnedSlice(allocator);
    }

    pub fn getBookmarkByMessageId(
        self: *MemoryStoreSqlite,
        persona_id: i64,
        message_id: i64,
    ) !?Types.Bookmark {
        const stmt = try self.db.prepare(
            "SELECT id, message_id, created_at_ms FROM bookmarks " ++
                "WHERE persona_id=? AND message_id=?;",
        );
        defer sqlite.finalize(stmt);

        sqlite.bindInt64(stmt, 1, persona_id);
        sqlite.bindInt64(stmt, 2, message_id);

        if (sqlite.step(stmt) != c.SQLITE_ROW) return null;

        return .{
            .id = sqlite.columnInt64(stmt, 0),
            .message_id = sqlite.columnInt64(stmt, 1),
            .created_at_ms = sqlite.columnInt64(stmt, 2),
        };
    }

    pub fn isMessageBookmarked(
        self: *MemoryStoreSqlite,
        persona_id: i64,
        message_id: i64,
    ) bool {
        const bm = self.getBookmarkByMessageId(persona_id, message_id) catch {
            return false;
        };
        return bm != null;
    }

    pub fn loadBookmarkedMessageIds(
        self: *MemoryStoreSqlite,
        allocator: std.mem.Allocator,
        persona_id: i64,
    ) ![]i64 {
        const stmt = try self.db.prepare(
            "SELECT message_id FROM bookmarks WHERE persona_id=?;",
        );
        defer sqlite.finalize(stmt);

        sqlite.bindInt64(stmt, 1, persona_id);

        var out: std.ArrayList(i64) = .empty;
        errdefer out.deinit(allocator);

        while (sqlite.step(stmt) == c.SQLITE_ROW) {
            try out.append(allocator, sqlite.columnInt64(stmt, 0));
        }

        return out.toOwnedSlice(allocator);
    }
};

pub fn freeProviderProfile(
    allocator: std.mem.Allocator,
    p: Types.ProviderProfile,
) void {
    allocator.free(@constCast(p.name));
    allocator.free(@constCast(p.ollama_url));
    allocator.free(@constCast(p.model));
    if (p.digest.len > 0) allocator.free(@constCast(p.digest));
    if (p.modified_at.len > 0) allocator.free(@constCast(p.modified_at));
}

pub fn freePersonaStrings(
    allocator: std.mem.Allocator,
    p: Types.PersonaProfile,
) void {
    allocator.free(@constCast(p.name));
    allocator.free(@constCast(p.ai_name));
    allocator.free(@constCast(p.tone));
    allocator.free(@constCast(p.persona_kernel));
}

pub fn freeIdentityPreset(
    allocator: std.mem.Allocator,
    p: Types.IdentityPreset,
) void {
    allocator.free(@constCast(p.name));
    allocator.free(@constCast(p.text));
}

pub const EventKind = enum(u8) {
    memory_proposed = 0,
    memory_stored = 1,
    memory_decayed = 2,
    memory_rejected = 3,
    episode_compacted = 4,
    thought_generated = 5,
    governor_blocked = 6,
    governor_accepted = 7,
    context_built = 8,
    chat_completed = 9,
    security_warning = 10,
    command_executed = 11,
};

pub const Event = struct {
    id: i64 = 0,
    kind: EventKind,
    timestamp_ms: i64,
    subject: []const u8,
    details: []const u8,
    session_id: ?[]const u8 = null,
};

pub const MessageRow = struct {
    id: i64,
    role: Types.Role,
    content: []const u8,
    created_at_ms: i64,
};

test "MemoryStoreSqlite schema creation" {
    var store = try MemoryStoreSqlite.init(":memory:");
    defer store.deinit();
    try store.ensureSchema();

    const count = try store.countMessages();
    try std.testing.expectEqual(@as(usize, 0), count);
}

test "MemoryStoreSqlite message round-trip" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var store = try MemoryStoreSqlite.init(":memory:");
    defer store.deinit();
    try store.ensureSchema();

    try store.insertMessage(allocator, .user, "hello");
    try store.insertMessage(allocator, .assistant, "hi there");

    const msgs = try store.loadRecentMessages(allocator, 10);
    defer {
        for (msgs) |m| allocator.free(@constCast(m.content));
        allocator.free(msgs);
    }

    try std.testing.expectEqual(@as(usize, 2), msgs.len);
    try std.testing.expectEqualStrings("hello", msgs[0].content);
    try std.testing.expectEqualStrings("hi there", msgs[1].content);
}

test "MemoryStoreSqlite memory conflict resolution" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var store = try MemoryStoreSqlite.init(":memory:");
    defer store.deinit();
    try store.ensureSchema();

    const policy = MemoryPolicy{};

    _ = try store.addMemoryGoverned(allocator, policy, .{
        .kind = .note,
        .subject = "user",
        .predicate = "intent",
        .object = "wants A",
        .confidence = 0.6,
        .is_active = true,
    });

    _ = try store.addMemoryGoverned(allocator, policy, .{
        .kind = .note,
        .subject = "user",
        .predicate = "intent",
        .object = "wants B",
        .confidence = 0.9,
        .is_active = true,
    });

    const active = try store.countActiveMemories();
    try std.testing.expectEqual(@as(usize, 1), active);

    const items = try store.loadMemoryItems(allocator, 10);
    defer {
        for (items) |m| {
            allocator.free(@constCast(m.subject));
            allocator.free(@constCast(m.predicate));
            allocator.free(@constCast(m.object));
        }
        allocator.free(items);
    }

    try std.testing.expectEqualStrings("wants B", items[0].object);
}
