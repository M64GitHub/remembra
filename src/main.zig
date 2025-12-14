const std = @import("std");
const version = @import("version.zig");
const Types = @import("Types.zig");
const ProviderMock = @import("Provider.zig").Provider;
const ProviderOllama = @import("ProviderOllama.zig").ProviderOllama;
const MemoryStoreMock = @import("MemoryStoreMock.zig").MemoryStoreMock;
const MemoryStoreSqlite = @import("MemoryStoreSqlite.zig").MemoryStoreSqlite;
const PromptBuilder = @import("PromptBuilder.zig").PromptBuilder;
const Reflector = @import("Reflector.zig").Reflector;
const Governor = @import("Governor.zig").Governor;
const MemoryPolicy = @import("MemoryPolicy.zig").MemoryPolicy;
const Cli = @import("Cli.zig").Cli;
const EpisodeCompactor = @import("EpisodeCompactor.zig").EpisodeCompactor;
const InjectionGuard = @import("InjectionGuard.zig");
const Intent = @import("Intent.zig");
const IdleThinker = @import("IdleThinker.zig").IdleThinker;
const Retrieval = @import("Retrieval.zig").Retrieval;

const USE_SQLITE = true;
const USE_OLLAMA = true;
const OLLAMA_URL = "http://127.0.0.1:11434";
const OLLAMA_MODEL = "llama3.2";

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

fn printHistory(cli: *Cli, msgs: []const Types.Message) void {
    if (msgs.len == 0) {
        cli.msg(.inf, "No messages.", .{});
        return;
    }
    for (msgs) |m| {
        const kind: Cli.MsgKind = switch (m.role) {
            .user => .snd,
            .assistant => .ok,
            .system => .st2,
        };
        cli.msg(kind, "{s}", .{m.content});
    }
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var cli = try Cli.init(allocator);
    defer cli.deinit(allocator);
    cli.app_prefix = "REMEMBRA";
    cli.show_timestamp = false;
    // cli.debug_level = 1;
    try cli.enableLogmode("REMEMBRA.log");

    cli.msg(.inf, "Starting up ...", .{});

    const Provider = if (USE_OLLAMA) ProviderOllama else ProviderMock;

    var provider = if (USE_OLLAMA)
        try ProviderOllama.init(allocator, OLLAMA_URL, OLLAMA_MODEL)
    else
        ProviderMock.init();
    defer if (USE_OLLAMA) provider.deinit(allocator) else provider.deinit();

    _ = Provider;

    const Store = if (USE_SQLITE) MemoryStoreSqlite else MemoryStoreMock;

    var store = if (USE_SQLITE)
        try MemoryStoreSqlite.init("remembra.db")
    else
        MemoryStoreMock.init(allocator);
    defer if (USE_SQLITE) store.deinit() else store.deinit(allocator);

    if (USE_SQLITE) {
        try store.ensureSchema();
        cli.msg(.ok, "SQLite store: remembra.db", .{});
    }

    const policy = MemoryPolicy{};
    _ = Store;

    const stdin_file: std.fs.File = .{ .handle = std.posix.STDIN_FILENO };

    cli.msg(.hil, "{s} {s}", .{ version.name, version.version });
    if (USE_OLLAMA) {
        cli.msg(.inf, "Ollama provider ({s}).", .{OLLAMA_MODEL});
    } else {
        cli.msg(.inf, "Mock provider.", .{});
    }
    if (USE_SQLITE) {
        cli.msg(
            .inf,
            "Commands: /db init/clear/stats, /mem add/ls/decay, " ++
                "/history [all|<hours>], /episode compact, " ++
                "/time advance, /idle run/tick, /quit",
            .{},
        );
    } else {
        cli.msg(
            .inf,
            "Commands: /mem add/ls/decay, /history [all|<hours>], " ++
                "/episode compact, /time advance, /idle run/tick, /quit",
            .{},
        );
    }

    while (true) {
        cli.prompt("You: ", .{});

        var line_buf: [4096]u8 = undefined;
        const line_opt = try readLine(stdin_file, &line_buf);
        if (line_opt == null) break;

        const line = std.mem.trimRight(u8, line_opt.?, "\r\n");
        if (line.len == 0) continue;

        if (std.mem.eql(u8, line, "/quit")) break;

        if (USE_SQLITE and std.mem.eql(u8, line, "/db init")) {
            try store.ensureSchema();
            cli.msg(.ok, "Schema ensured.", .{});
            continue;
        }

        if (USE_SQLITE and std.mem.eql(u8, line, "/db clear")) {
            try store.clearDb();
            cli.msg(.ok, "Database cleared.", .{});
            continue;
        }

        if (USE_SQLITE and std.mem.eql(u8, line, "/db stats")) {
            const mc = store.countMessages() catch 0;
            const mm = store.countMemories() catch 0;
            const ma = store.countActiveMemories() catch 0;
            cli.msg(
                .inf,
                "messages={d} memories={d} active={d}",
                .{ mc, mm, ma },
            );
            continue;
        }

        if (std.mem.eql(u8, line, "/mem ls")) {
            const all = try store.loadAllMemoryItems(allocator);
            defer {
                if (USE_SQLITE) {
                    for (all) |m| {
                        allocator.free(@constCast(m.subject));
                        allocator.free(@constCast(m.predicate));
                        allocator.free(@constCast(m.object));
                    }
                }
                allocator.free(all);
            }

            if (all.len == 0) {
                cli.msg(.inf, "Memory: (empty)", .{});
                continue;
            }

            cli.msg(.inf, "Memory:", .{});
            for (all) |m| {
                cli.msg(
                    .st2,
                    "- [mem#{d}] {s} {s}.{s}={s} (conf {d:.2}) {s}",
                    .{
                        m.id,
                        Types.kindToStr(m.kind),
                        m.subject,
                        m.predicate,
                        m.object,
                        m.confidence,
                        if (m.is_active) "active" else "inactive",
                    },
                );
            }
            continue;
        }

        if (std.mem.startsWith(u8, line, "/mem add ")) {
            const rest = line["/mem add ".len..];
            if (rest.len == 0) {
                cli.msg(.wrn, "Usage: /mem add <text>", .{});
                continue;
            }

            const id = try store.addMemoryGoverned(allocator, policy, .{
                .kind = .note,
                .subject = "user",
                .predicate = "says",
                .object = rest,
                .confidence = 0.7,
                .is_active = true,
            });

            cli.msg(.ok, "Stored memory as [mem#{d}].", .{id});
            continue;
        }

        if (std.mem.startsWith(u8, line, "/mem decay ")) {
            const rest = line["/mem decay ".len..];
            const hours = std.fmt.parseInt(i64, rest, 10) catch {
                cli.msg(.wrn, "Usage: /mem decay <hours>", .{});
                continue;
            };
            const now = store.nowMs();
            const simulated_now = now + hours * 60 * 60 * 1000;

            store.decayMemory(policy, simulated_now);

            cli.msg(.ok, "Decayed memory by ~{d} hours.", .{hours});

            const mem = try store.loadMemoryItems(allocator, 50);
            defer {
                if (USE_SQLITE) {
                    for (mem) |m| {
                        allocator.free(@constCast(m.subject));
                        allocator.free(@constCast(m.predicate));
                        allocator.free(@constCast(m.object));
                    }
                }
                allocator.free(mem);
            }
            for (mem) |m| {
                cli.msg(.st2, "- [mem#{d}] {s}.{s}={s} (conf {d:.2})", .{
                    m.id, m.subject, m.predicate, m.object, m.confidence,
                });
            }
            continue;
        }

        if (std.mem.startsWith(u8, line, "/time advance ")) {
            const rest = line["/time advance ".len..];
            const hours = std.fmt.parseInt(i64, rest, 10) catch {
                cli.msg(.wrn, "Usage: /time advance <hours>", .{});
                continue;
            };
            store.advanceTimeHours(hours);
            cli.msg(.ok, "Advanced simulated time by {d} hours.", .{hours});
            continue;
        }

        if (std.mem.eql(u8, line, "/history")) {
            const msgs = try store.loadRecentMessages(allocator, 50);
            defer {
                if (USE_SQLITE) {
                    for (msgs) |m| allocator.free(@constCast(m.content));
                }
                allocator.free(msgs);
            }
            printHistory(cli, msgs);
            continue;
        }

        if (std.mem.eql(u8, line, "/history all")) {
            const msgs = try store.loadAllMessages(allocator);
            defer {
                if (USE_SQLITE) {
                    for (msgs) |m| allocator.free(@constCast(m.content));
                }
                allocator.free(msgs);
            }
            printHistory(cli, msgs);
            continue;
        }

        if (std.mem.startsWith(u8, line, "/history ")) {
            const rest = line["/history ".len..];
            const hours = std.fmt.parseInt(i64, rest, 10) catch {
                cli.msg(.wrn, "Usage: /history [all|<hours>]", .{});
                continue;
            };
            const since_ms = store.nowMs() - (hours * 60 * 60 * 1000);
            const msgs = try store.loadMessagesSince(allocator, since_ms);
            defer {
                if (USE_SQLITE) {
                    for (msgs) |m| allocator.free(@constCast(m.content));
                }
                allocator.free(msgs);
            }
            printHistory(cli, msgs);
            continue;
        }

        if (std.mem.eql(u8, line, "/idle run")) {
            const now_ms = store.nowMs();
            try IdleThinker.maybeRun(
                allocator,
                &provider,
                &store,
                policy,
                cli,
                .{},
                now_ms,
            );
            continue;
        }

        if (std.mem.startsWith(u8, line, "/idle tick ")) {
            const rest = line["/idle tick ".len..];
            const minutes = std.fmt.parseInt(i64, rest, 10) catch {
                cli.msg(.wrn, "Usage: /idle tick <minutes>", .{});
                continue;
            };
            store.advanceTimeMinutes(minutes);
            const now_ms = store.nowMs();
            try IdleThinker.maybeRun(
                allocator,
                &provider,
                &store,
                policy,
                cli,
                .{},
                now_ms,
            );
            cli.msg(.ok, "Idle ticked by {d} minutes.", .{minutes});
            continue;
        }

        if (std.mem.eql(u8, line, "/episode compact")) {
            store.decayMemory(policy, store.nowMs());

            const ep_msgs = try store.loadMessagesSinceCutoff(allocator, 200);
            defer {
                if (USE_SQLITE) {
                    for (ep_msgs) |m| allocator.free(@constCast(m.content));
                }
                allocator.free(ep_msgs);
            }

            if (ep_msgs.len == 0) {
                cli.msg(
                    .inf,
                    "No new messages since last episode cutoff (index {d}).",
                    .{store.getEpisodeCutoffIndex()},
                );
                continue;
            }

            const ep = try EpisodeCompactor.run(allocator, &provider, ep_msgs);
            defer {
                allocator.free(ep.title);
                allocator.free(ep.summary);
            }

            const combined = try std.fmt.allocPrint(
                allocator,
                "{s}\n{s}",
                .{ ep.title, ep.summary },
            );
            defer allocator.free(combined);

            const id = try store.addMemoryGoverned(allocator, policy, .{
                .kind = .note,
                .subject = "episode",
                .predicate = "summary",
                .object = combined,
                .confidence = 0.85,
                .is_active = true,
            });

            store.advanceEpisodeCutoffToEnd();

            cli.msg(
                .ok,
                "Stored episode summary as [mem#{d}] and advanced cutoff to {d}.",
                .{ id, store.getEpisodeCutoffIndex() },
            );
            continue;
        }

        const guard = InjectionGuard.check(line);
        if (guard.is_attack) {
            cli.msg(
                .wrn,
                "Input looks like prompt-injection (reason: {s}). Memory ops disabled.",
                .{guard.reason},
            );
        }
        const intent = Intent.classifyMemoryIntent(line);
        const allow_memory_ops = !guard.is_attack and (intent == .explicit_store);

        const identity = try store.loadIdentityCore(allocator);
        defer {
            if (USE_SQLITE) {
                for (identity) |e| {
                    allocator.free(@constCast(e.key));
                    allocator.free(@constCast(e.value));
                }
            }
            allocator.free(identity);
        }

        const now_ms = store.nowMs();
        store.decayMemory(policy, now_ms);

        try IdleThinker.maybeRun(
            allocator,
            &provider,
            &store,
            policy,
            cli,
            .{},
            now_ms,
        );

        const candidates = try store.loadMemoryCandidates(allocator, 200);
        defer {
            if (USE_SQLITE) {
                for (candidates) |m| {
                    allocator.free(@constCast(m.subject));
                    allocator.free(@constCast(m.predicate));
                    allocator.free(@constCast(m.object));
                }
            }
            allocator.free(candidates);
        }

        const selected_idxs = try Retrieval.select(
            allocator,
            candidates,
            line,
            now_ms,
            .{},
        );
        defer allocator.free(selected_idxs);

        const memory = try allocator.alloc(Types.MemoryItem, selected_idxs.len);
        defer allocator.free(memory);
        for (selected_idxs, 0..) |idx, j| {
            memory[j] = candidates[idx];
        }

        const recent = try store.loadRecentMessages(allocator, 24);
        defer {
            if (USE_SQLITE) {
                for (recent) |m| allocator.free(@constCast(m.content));
            }
            allocator.free(recent);
        }

        const last_user_ms = store.getLastUserMsgMs();

        const last_episode = store.latestActiveObjectByKey("episode", "summary");
        const last_thought = store.latestActiveObjectByKey("self", "thought");

        try store.insertMessage(allocator, .user, line);

        cli.msg(.dbg, "injecting {d} memory items", .{memory.len});
        cli.msg(.dbg, "injecting {d} recent messages", .{recent.len});

        const model_msgs = try PromptBuilder.build(
            allocator,
            identity,
            memory,
            recent,
            line,
            now_ms,
            last_user_ms,
            last_episode,
            last_thought,
        );
        defer {
            if (model_msgs.len != 0 and model_msgs[0].role == .system) {
                allocator.free(@constCast(model_msgs[0].content));
            }
            allocator.free(model_msgs);
        }

        cli.msg(.dbg, "prompt total messages: {d}", .{model_msgs.len});
        for (model_msgs, 0..) |msg, i| {
            cli.msg(.dbg, "[{d}] {s}: {s}", .{
                i,
                Types.roleToStr(msg.role),
                msg.content,
            });
        }

        const reply = try provider.chat(
            allocator,
            model_msgs,
            .{ .model = "mock", .temperature = 0.7, .max_tokens = 256 },
        );
        defer allocator.free(reply);

        try store.insertMessage(allocator, .assistant, reply);

        cli.msg(.ok, "{s}", .{reply});

        const recent_for_reflection = try store.loadRecentMessages(allocator, 24);
        defer {
            if (USE_SQLITE) {
                for (recent_for_reflection) |m| allocator.free(@constCast(m.content));
            }
            allocator.free(recent_for_reflection);
        }

        const proposals = try Reflector.run(
            allocator,
            &provider,
            identity,
            memory,
            recent_for_reflection,
            reply,
            allow_memory_ops,
            cli,
        );
        defer {
            for (proposals) |p| {
                allocator.free(@constCast(p.subject));
                allocator.free(@constCast(p.predicate));
                allocator.free(@constCast(p.object));
            }
            allocator.free(proposals);
        }

        if (proposals.len != 0) {
            cli.msg(.hil, "[Governor evaluation]", .{});
            try Governor.apply(allocator, &store, policy, proposals, cli);
        }
    }
}
