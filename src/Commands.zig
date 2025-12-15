//! Command handling for REMEMBRA slash commands.

const std = @import("std");
const Types = @import("Types.zig");
const Cli = @import("Cli.zig").Cli;
const MemoryStoreSqlite = @import("MemoryStoreSqlite.zig").MemoryStoreSqlite;
const ProviderOllama = @import("ProviderOllama.zig").ProviderOllama;
const IdleThinker = @import("IdleThinker.zig").IdleThinker;
const EpisodeCompactor = @import("EpisodeCompactor.zig").EpisodeCompactor;

const ConfigConn = @import("ConfigConnection.zig").ConfigConnection;
const ConfigSys = @import("ConfigSystem.zig").ConfigSystem;
const ConfigIdent = @import("ConfigIdentity.zig").ConfigIdentity;
const MemoryPolicy = @import("MemoryPolicy.zig").MemoryPolicy;

pub const Context = struct {
    allocator: std.mem.Allocator,
    cli: *Cli,
    store: *MemoryStoreSqlite,
    provider: *ProviderOllama,
    conn: ConfigConn,
    sys: ConfigSys,
    ident: ConfigIdent,
    policy: MemoryPolicy,
};

pub const Result = enum {
    handled,
    not_command,
    quit,
};

pub const Commands = struct {
    pub fn execute(ctx: *Context, line: []const u8) !Result {
        if (std.mem.eql(u8, line, "/quit")) return .quit;
        if (std.mem.eql(u8, line, "/help")) return cmdHelp(ctx);

        if (std.mem.eql(u8, line, "/db init")) return cmdDbInit(ctx);
        if (std.mem.eql(u8, line, "/db clear")) return cmdDbClear(ctx);
        if (std.mem.eql(u8, line, "/db stats")) return cmdDbStats(ctx);

        if (std.mem.eql(u8, line, "/mem ls")) return cmdMemLs(ctx);
        if (std.mem.startsWith(u8, line, "/mem add "))
            return cmdMemAdd(ctx, line["/mem add ".len..]);
        if (std.mem.startsWith(u8, line, "/mem decay "))
            return cmdMemDecay(ctx, line["/mem decay ".len..]);

        if (std.mem.startsWith(u8, line, "/time advance "))
            return cmdTimeAdvance(ctx, line["/time advance ".len..]);

        if (std.mem.eql(u8, line, "/history")) return cmdHistory(ctx);
        if (std.mem.eql(u8, line, "/history all")) return cmdHistoryAll(ctx);
        if (std.mem.startsWith(u8, line, "/history "))
            return cmdHistoryHours(ctx, line["/history ".len..]);

        if (std.mem.eql(u8, line, "/idle run")) return cmdIdleRun(ctx);
        if (std.mem.startsWith(u8, line, "/idle tick "))
            return cmdIdleTick(ctx, line["/idle tick ".len..]);

        if (std.mem.eql(u8, line, "/episode compact"))
            return cmdEpisodeCompact(ctx);

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

    fn cmdHelp(ctx: *Context) Result {
        ctx.cli.msg(.inf, "{s}", .{help()});
        return .handled;
    }

    fn cmdDbInit(ctx: *Context) !Result {
        try ctx.store.ensureSchema();
        ctx.cli.msg(.ok, "Schema ensured.", .{});
        return .handled;
    }

    fn cmdDbClear(ctx: *Context) !Result {
        try ctx.store.clearDb();
        ctx.cli.msg(.ok, "Database cleared.", .{});
        return .handled;
    }

    fn cmdDbStats(ctx: *Context) Result {
        const mc = ctx.store.countMessages() catch 0;
        const mm = ctx.store.countMemories() catch 0;
        const ma = ctx.store.countActiveMemories() catch 0;
        ctx.cli.msg(
            .inf,
            "messages={d} memories={d} active={d}",
            .{ mc, mm, ma },
        );
        return .handled;
    }

    fn cmdMemLs(ctx: *Context) !Result {
        const all = try ctx.store.loadAllMemoryItems(ctx.allocator);
        defer {
            for (all) |m| {
                ctx.allocator.free(@constCast(m.subject));
                ctx.allocator.free(@constCast(m.predicate));
                ctx.allocator.free(@constCast(m.object));
            }
            ctx.allocator.free(all);
        }

        if (all.len == 0) {
            ctx.cli.msg(.inf, "Memory: (empty)", .{});
            return .handled;
        }

        ctx.cli.msg(.inf, "Memory:", .{});
        for (all) |m| {
            ctx.cli.msg(
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

    fn cmdMemAdd(ctx: *Context, text: []const u8) !Result {
        if (text.len == 0) {
            ctx.cli.msg(.wrn, "Usage: /mem add <text>", .{});
            return .handled;
        }

        const id = try ctx.store.addMemoryGoverned(ctx.allocator, ctx.policy, .{
            .kind = .note,
            .subject = "user",
            .predicate = "says",
            .object = text,
            .confidence = ctx.ident.confidence_user_notes,
            .is_active = true,
        });

        ctx.cli.msg(.ok, "Stored memory as [mem#{d}].", .{id});
        return .handled;
    }

    fn cmdMemDecay(ctx: *Context, arg: []const u8) !Result {
        const hours = std.fmt.parseInt(i64, arg, 10) catch {
            ctx.cli.msg(.wrn, "Usage: /mem decay <hours>", .{});
            return .handled;
        };
        const now = ctx.store.nowMs();
        const simulated_now = now + hours * 60 * 60 * 1000;

        ctx.store.decayMemory(ctx.policy, simulated_now);

        ctx.cli.msg(.ok, "Decayed memory by ~{d} hours.", .{hours});

        const mem = try ctx.store.loadMemoryItems(
            ctx.allocator,
            ctx.sys.max_history_display,
        );
        defer {
            for (mem) |m| {
                ctx.allocator.free(@constCast(m.subject));
                ctx.allocator.free(@constCast(m.predicate));
                ctx.allocator.free(@constCast(m.object));
            }
            ctx.allocator.free(mem);
        }
        for (mem) |m| {
            ctx.cli.msg(.st2, "- [mem#{d}] {s}.{s}={s} (conf {d:.2})", .{
                m.id, m.subject, m.predicate, m.object, m.confidence,
            });
        }
        return .handled;
    }

    fn cmdTimeAdvance(ctx: *Context, arg: []const u8) Result {
        const hours = std.fmt.parseInt(i64, arg, 10) catch {
            ctx.cli.msg(.wrn, "Usage: /time advance <hours>", .{});
            return .handled;
        };
        ctx.store.advanceTimeHours(hours);
        ctx.cli.msg(.ok, "Advanced simulated time by {d} hours.", .{hours});
        return .handled;
    }

    fn cmdHistory(ctx: *Context) !Result {
        const msgs = try ctx.store.loadRecentMessages(
            ctx.allocator,
            ctx.sys.max_history_display,
        );
        defer {
            for (msgs) |m| ctx.allocator.free(@constCast(m.content));
            ctx.allocator.free(msgs);
        }
        printHistory(ctx.cli, msgs);
        return .handled;
    }

    fn cmdHistoryAll(ctx: *Context) !Result {
        const msgs = try ctx.store.loadAllMessages(ctx.allocator);
        defer {
            for (msgs) |m| ctx.allocator.free(@constCast(m.content));
            ctx.allocator.free(msgs);
        }
        printHistory(ctx.cli, msgs);
        return .handled;
    }

    fn cmdHistoryHours(ctx: *Context, arg: []const u8) !Result {
        const hours = std.fmt.parseInt(i64, arg, 10) catch {
            ctx.cli.msg(.wrn, "Usage: /history [all|<hours>]", .{});
            return .handled;
        };
        const since_ms = ctx.store.nowMs() - (hours * 60 * 60 * 1000);
        const msgs = try ctx.store.loadMessagesSince(ctx.allocator, since_ms);
        defer {
            for (msgs) |m| ctx.allocator.free(@constCast(m.content));
            ctx.allocator.free(msgs);
        }
        printHistory(ctx.cli, msgs);
        return .handled;
    }

    fn cmdIdleRun(ctx: *Context) !Result {
        const now_ms = ctx.store.nowMs();
        try IdleThinker.maybeRun(
            ctx.allocator,
            ctx.provider,
            ctx.store,
            ctx.policy,
            ctx.cli,
            ctx.sys.idle_params,
            now_ms,
            ctx.ident.llm_idle,
            ctx.ident.llm_episode,
            ctx.ident.confidence_idle_thoughts,
            ctx.ident.confidence_episodes,
        );
        return .handled;
    }

    fn cmdIdleTick(ctx: *Context, arg: []const u8) !Result {
        const minutes = std.fmt.parseInt(i64, arg, 10) catch {
            ctx.cli.msg(.wrn, "Usage: /idle tick <minutes>", .{});
            return .handled;
        };
        ctx.store.advanceTimeMinutes(minutes);
        const now_ms = ctx.store.nowMs();
        try IdleThinker.maybeRun(
            ctx.allocator,
            ctx.provider,
            ctx.store,
            ctx.policy,
            ctx.cli,
            ctx.sys.idle_params,
            now_ms,
            ctx.ident.llm_idle,
            ctx.ident.llm_episode,
            ctx.ident.confidence_idle_thoughts,
            ctx.ident.confidence_episodes,
        );
        ctx.cli.msg(.ok, "Idle ticked by {d} minutes.", .{minutes});
        return .handled;
    }

    fn cmdEpisodeCompact(ctx: *Context) !Result {
        ctx.store.decayMemory(ctx.policy, ctx.store.nowMs());

        const ep_msgs = try ctx.store.loadMessagesSinceCutoff(
            ctx.allocator,
            ctx.sys.max_episode_messages,
        );
        defer {
            for (ep_msgs) |m| ctx.allocator.free(@constCast(m.content));
            ctx.allocator.free(ep_msgs);
        }

        if (ep_msgs.len == 0) {
            ctx.cli.msg(
                .inf,
                "No new messages since last episode cutoff (index {d}).",
                .{ctx.store.getEpisodeCutoffIndex()},
            );
            return .handled;
        }

        const ep = try EpisodeCompactor.run(
            ctx.allocator,
            ctx.provider,
            ep_msgs,
            ctx.ident.llm_episode,
        );
        defer {
            ctx.allocator.free(ep.title);
            ctx.allocator.free(ep.summary);
        }

        const combined = try std.fmt.allocPrint(
            ctx.allocator,
            "{s}\n{s}",
            .{ ep.title, ep.summary },
        );
        defer ctx.allocator.free(combined);

        const id = try ctx.store.addMemoryGoverned(ctx.allocator, ctx.policy, .{
            .kind = .note,
            .subject = "episode",
            .predicate = "summary",
            .object = combined,
            .confidence = ctx.ident.confidence_episodes,
            .is_active = true,
        });

        ctx.store.advanceEpisodeCutoffToEnd();

        ctx.cli.msg(
            .ok,
            "Stored episode summary as [mem#{d}] and advanced cutoff to {d}.",
            .{ id, ctx.store.getEpisodeCutoffIndex() },
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
};
