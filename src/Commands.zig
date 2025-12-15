//! Command handling for REMEMBRA slash commands.

const std = @import("std");
const Types = @import("Types.zig");
const Cli = @import("Cli.zig").Cli;
const IdleThinker = @import("IdleThinker.zig").IdleThinker;
const EpisodeCompactor = @import("EpisodeCompactor.zig").EpisodeCompactor;
const App = @import("App.zig").App;

pub const Result = enum {
    handled,
    not_command,
    quit,
};

pub fn execute(
    allocator: std.mem.Allocator,
    app: *App,
    line: []const u8,
) !Result {
    if (std.mem.eql(u8, line, "/quit")) return .quit;
    if (std.mem.eql(u8, line, "/help")) return cmdHelp(app);

    if (std.mem.eql(u8, line, "/db init")) return cmdDbInit(app);
    if (std.mem.eql(u8, line, "/db clear")) return cmdDbClear(app);
    if (std.mem.eql(u8, line, "/db stats")) return cmdDbStats(app);

    if (std.mem.eql(u8, line, "/mem ls")) return cmdMemLs(allocator, app);
    if (std.mem.startsWith(u8, line, "/mem add "))
        return cmdMemAdd(allocator, app, line["/mem add ".len..]);
    if (std.mem.startsWith(u8, line, "/mem decay "))
        return cmdMemDecay(allocator, app, line["/mem decay ".len..]);

    if (std.mem.startsWith(u8, line, "/time advance "))
        return cmdTimeAdvance(app, line["/time advance ".len..]);

    if (std.mem.eql(u8, line, "/history"))
        return cmdHistory(allocator, app);
    if (std.mem.eql(u8, line, "/history all"))
        return cmdHistoryAll(allocator, app);
    if (std.mem.startsWith(u8, line, "/history "))
        return cmdHistoryHours(allocator, app, line["/history ".len..]);

    if (std.mem.eql(u8, line, "/idle run"))
        return cmdIdleRun(allocator, app);
    if (std.mem.startsWith(u8, line, "/idle tick "))
        return cmdIdleTick(allocator, app, line["/idle tick ".len..]);

    if (std.mem.eql(u8, line, "/episode compact"))
        return cmdEpisodeCompact(allocator, app);

    return .not_command;
}

pub fn help() []const u8 {
    return 
    \\Commands:
    \\  /quit              - Exit the program
    \\  /help              - Show this help
    \\  /db init           - Initialize database schema
    \\  /db clear          - Clear all database data
    \\  /db stats          - Show database statistics
    \\  /mem ls            - List all memory items
    \\  /mem add <text>    - Store a user note
    \\  /mem decay <hours> - Simulate memory decay
    \\  /time advance <h>  - Advance simulated time
    \\  /history           - Show recent messages
    \\  /history all       - Show all messages
    \\  /history <hours>   - Show messages from past N hours
    \\  /idle run          - Trigger idle thinking
    \\  /idle tick <min>   - Advance time + idle think
    \\  /episode compact   - Compact messages into episode
    ;
}

fn cmdHelp(app: *App) Result {
    app.cli.msg(.inf, "{s}", .{help()});
    return .handled;
}

fn cmdDbInit(app: *App) !Result {
    try app.store.ensureSchema();
    app.cli.msg(.ok, "Schema ensured.", .{});
    return .handled;
}

fn cmdDbClear(app: *App) !Result {
    try app.store.clearDb();
    app.cli.msg(.ok, "Database cleared.", .{});
    return .handled;
}

fn cmdDbStats(app: *App) Result {
    const mc = app.store.countMessages() catch 0;
    const mm = app.store.countMemories() catch 0;
    const ma = app.store.countActiveMemories() catch 0;
    app.cli.msg(
        .inf,
        "messages={d} memories={d} active={d}",
        .{ mc, mm, ma },
    );
    return .handled;
}

fn cmdMemLs(allocator: std.mem.Allocator, app: *App) !Result {
    const all = try app.store.loadAllMemoryItems(allocator);
    defer {
        for (all) |m| {
            allocator.free(@constCast(m.subject));
            allocator.free(@constCast(m.predicate));
            allocator.free(@constCast(m.object));
        }
        allocator.free(all);
    }

    if (all.len == 0) {
        app.cli.msg(.inf, "Memory: (empty)", .{});
        return .handled;
    }

    app.cli.msg(.inf, "Memory:", .{});
    for (all) |m| {
        app.cli.msg(
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
    return .handled;
}

fn cmdMemAdd(
    allocator: std.mem.Allocator,
    app: *App,
    text: []const u8,
) !Result {
    if (text.len == 0) {
        app.cli.msg(.wrn, "Usage: /mem add <text>", .{});
        return .handled;
    }

    const policy = app.ident.memory_policy;
    const id = try app.store.addMemoryGoverned(allocator, policy, .{
        .kind = .note,
        .subject = "user",
        .predicate = "says",
        .object = text,
        .confidence = app.ident.confidence_user_notes,
        .is_active = true,
    });

    app.cli.msg(.ok, "Stored memory as [mem#{d}].", .{id});
    return .handled;
}

fn cmdMemDecay(
    allocator: std.mem.Allocator,
    app: *App,
    arg: []const u8,
) !Result {
    const hours = std.fmt.parseInt(i64, arg, 10) catch {
        app.cli.msg(.wrn, "Usage: /mem decay <hours>", .{});
        return .handled;
    };
    const now = app.store.nowMs();
    const simulated_now = now + hours * 60 * 60 * 1000;
    const policy = app.ident.memory_policy;

    app.store.decayMemory(policy, simulated_now);

    app.cli.msg(.ok, "Decayed memory by ~{d} hours.", .{hours});

    const mem = try app.store.loadMemoryItems(
        allocator,
        app.sys.max_history_display,
    );
    defer {
        for (mem) |m| {
            allocator.free(@constCast(m.subject));
            allocator.free(@constCast(m.predicate));
            allocator.free(@constCast(m.object));
        }
        allocator.free(mem);
    }
    for (mem) |m| {
        app.cli.msg(.st2, "- [mem#{d}] {s}.{s}={s} (conf {d:.2})", .{
            m.id, m.subject, m.predicate, m.object, m.confidence,
        });
    }
    return .handled;
}

fn cmdTimeAdvance(app: *App, arg: []const u8) Result {
    const hours = std.fmt.parseInt(i64, arg, 10) catch {
        app.cli.msg(.wrn, "Usage: /time advance <hours>", .{});
        return .handled;
    };
    app.store.advanceTimeHours(hours);
    app.cli.msg(.ok, "Advanced simulated time by {d} hours.", .{hours});
    return .handled;
}

fn cmdHistory(allocator: std.mem.Allocator, app: *App) !Result {
    const msgs = try app.store.loadRecentMessages(
        allocator,
        app.sys.max_history_display,
    );
    defer {
        for (msgs) |m| allocator.free(@constCast(m.content));
        allocator.free(msgs);
    }
    printHistory(app.cli, msgs);
    return .handled;
}

fn cmdHistoryAll(allocator: std.mem.Allocator, app: *App) !Result {
    const msgs = try app.store.loadAllMessages(allocator);
    defer {
        for (msgs) |m| allocator.free(@constCast(m.content));
        allocator.free(msgs);
    }
    printHistory(app.cli, msgs);
    return .handled;
}

fn cmdHistoryHours(
    allocator: std.mem.Allocator,
    app: *App,
    arg: []const u8,
) !Result {
    const hours = std.fmt.parseInt(i64, arg, 10) catch {
        app.cli.msg(.wrn, "Usage: /history [all|<hours>]", .{});
        return .handled;
    };
    const since_ms = app.store.nowMs() - (hours * 60 * 60 * 1000);
    const msgs = try app.store.loadMessagesSince(allocator, since_ms);
    defer {
        for (msgs) |m| allocator.free(@constCast(m.content));
        allocator.free(msgs);
    }
    printHistory(app.cli, msgs);
    return .handled;
}

fn cmdIdleRun(allocator: std.mem.Allocator, app: *App) !Result {
    const now_ms = app.store.nowMs();
    const policy = app.ident.memory_policy;
    try IdleThinker.maybeRun(
        allocator,
        &app.provider,
        &app.store,
        policy,
        app.cli,
        app.sys.idle_params,
        now_ms,
        app.ident.llm_idle,
        app.ident.llm_episode,
        app.ident.confidence_idle_thoughts,
        app.ident.confidence_episodes,
    );
    return .handled;
}

fn cmdIdleTick(
    allocator: std.mem.Allocator,
    app: *App,
    arg: []const u8,
) !Result {
    const minutes = std.fmt.parseInt(i64, arg, 10) catch {
        app.cli.msg(.wrn, "Usage: /idle tick <minutes>", .{});
        return .handled;
    };
    app.store.advanceTimeMinutes(minutes);
    const now_ms = app.store.nowMs();
    const policy = app.ident.memory_policy;
    try IdleThinker.maybeRun(
        allocator,
        &app.provider,
        &app.store,
        policy,
        app.cli,
        app.sys.idle_params,
        now_ms,
        app.ident.llm_idle,
        app.ident.llm_episode,
        app.ident.confidence_idle_thoughts,
        app.ident.confidence_episodes,
    );
    app.cli.msg(.ok, "Idle ticked by {d} minutes.", .{minutes});
    return .handled;
}

fn cmdEpisodeCompact(allocator: std.mem.Allocator, app: *App) !Result {
    const policy = app.ident.memory_policy;
    app.store.decayMemory(policy, app.store.nowMs());

    const ep_msgs = try app.store.loadMessagesSinceCutoff(
        allocator,
        app.sys.max_episode_messages,
    );
    defer {
        for (ep_msgs) |m| allocator.free(@constCast(m.content));
        allocator.free(ep_msgs);
    }

    if (ep_msgs.len == 0) {
        app.cli.msg(
            .inf,
            "No new messages since last episode cutoff (index {d}).",
            .{app.store.getEpisodeCutoffIndex()},
        );
        return .handled;
    }

    const ep = try EpisodeCompactor.run(
        allocator,
        &app.provider,
        ep_msgs,
        app.ident.llm_episode,
    );
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

    const id = try app.store.addMemoryGoverned(allocator, policy, .{
        .kind = .note,
        .subject = "episode",
        .predicate = "summary",
        .object = combined,
        .confidence = app.ident.confidence_episodes,
        .is_active = true,
    });

    app.store.advanceEpisodeCutoffToEnd();

    app.cli.msg(
        .ok,
        "Stored episode summary as [mem#{d}] and advanced cutoff to {d}.",
        .{ id, app.store.getEpisodeCutoffIndex() },
    );
    return .handled;
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
