//! Conversation turn processing for REMEMBRA.

const std = @import("std");
const Types = @import("Types.zig");
const Cli = @import("Cli.zig").Cli;
const App = @import("App.zig").App;
const InjectionGuard = @import("InjectionGuard.zig");
const Intent = @import("Intent.zig");
const IdleThinker = @import("IdleThinker.zig").IdleThinker;
const Retrieval = @import("Retrieval.zig").Retrieval;
const PromptBuilder = @import("PromptBuilder.zig").PromptBuilder;
const Reflector = @import("Reflector.zig").Reflector;
const Governor = @import("Governor.zig").Governor;
const EventKind = @import("MemoryStoreSqlite.zig").EventKind;

const TurnContext = struct {
    identity: []const Types.IdentityEntry,
    memory: []const Types.MemoryItem,
    candidates: []const Types.MemoryItem,
    recent: []const Types.Message,
    now_ms: i64,
    last_user_ms: i64,
    last_episode: ?[]const u8,
    last_thought: ?[]const u8,

    pub fn deinit(self: *TurnContext, allocator: std.mem.Allocator) void {
        for (self.identity) |e| {
            allocator.free(@constCast(e.key));
            allocator.free(@constCast(e.value));
        }
        allocator.free(self.identity);

        for (self.candidates) |m| {
            allocator.free(@constCast(m.subject));
            allocator.free(@constCast(m.predicate));
            allocator.free(@constCast(m.object));
        }
        allocator.free(self.candidates);
        allocator.free(self.memory);

        for (self.recent) |m| allocator.free(@constCast(m.content));
        allocator.free(self.recent);
    }
};

pub fn processTurn(
    allocator: std.mem.Allocator,
    app: *App,
    user_input: []const u8,
) !void {
    const reply = try processAndReturn(allocator, app, user_input);
    defer allocator.free(reply);
    app.cli.msg(.rok, "{s}", .{reply});
}

pub fn processAndReturn(
    allocator: std.mem.Allocator,
    app: *App,
    user_input: []const u8,
) ![]u8 {
    const pid = app.store.getActivePersonaId() orelse 1;

    const allow_ops = checkSecurity(app, pid, user_input);

    try runIdleThinker(allocator, app, pid);

    var ctx = try gatherContext(allocator, app, pid);
    defer ctx.deinit(allocator);

    const reply = try generateReply(allocator, app, pid, &ctx, user_input);
    errdefer allocator.free(reply);

    try runReflection(allocator, app, pid, &ctx, reply, allow_ops);

    return reply;
}

fn checkSecurity(app: *App, pid: i64, input: []const u8) bool {
    const guard = InjectionGuard.check(input);
    if (guard.is_attack) {
        app.cli.msg(
            .wrn,
            "Input looks like prompt-injection (reason: {s}). " ++
                "Memory ops disabled.",
            .{guard.reason},
        );
        app.events.emit(pid, .security_warning, "injection", guard.reason);
    }
    const intent = Intent.classifyMemoryIntent(input);
    return !guard.is_attack and (intent == .explicit_store);
}

fn runIdleThinker(allocator: std.mem.Allocator, app: *App, pid: i64) !void {
    const now_ms = app.store.nowMs();
    const policy = app.ident.memory_policy;

    app.store.decayMemory(pid, policy, now_ms);

    try IdleThinker.maybeRun(
        allocator,
        &app.provider,
        &app.store,
        pid,
        policy,
        app.cli,
        &app.events,
        app.sys.idle_params,
        now_ms,
        app.ident.llm_idle,
        app.ident.llm_episode,
        app.ident.confidence_idle_thoughts,
        app.ident.confidence_episodes,
        app.ident.prompts,
        app.ident.name,
    );
}

fn gatherContext(allocator: std.mem.Allocator, app: *App, pid: i64) !TurnContext {
    const identity = try app.store.loadIdentityCoreWithDefaults(
        allocator,
        pid,
        .{
            .tone = app.ident.default_tone,
            .memory_contract = app.ident.default_memory_contract,
        },
    );
    errdefer {
        for (identity) |e| {
            allocator.free(@constCast(e.key));
            allocator.free(@constCast(e.value));
        }
        allocator.free(identity);
    }

    const now_ms = app.store.nowMs();

    const candidates = try app.store.loadMemoryCandidates(
        allocator,
        pid,
        app.sys.max_memory_candidates,
    );
    errdefer {
        for (candidates) |m| {
            allocator.free(@constCast(m.subject));
            allocator.free(@constCast(m.predicate));
            allocator.free(@constCast(m.object));
        }
        allocator.free(candidates);
    }

    const selected_idxs = try Retrieval.select(
        allocator,
        candidates,
        "",
        now_ms,
        app.sys.retrieval_params,
    );
    defer allocator.free(selected_idxs);

    const memory = try allocator.alloc(Types.MemoryItem, selected_idxs.len);
    for (selected_idxs, 0..) |idx, j| {
        memory[j] = candidates[idx];
    }

    const recent = try app.store.loadRecentMessages(
        allocator,
        pid,
        app.max_recent_messages,
    );
    errdefer {
        for (recent) |m| allocator.free(@constCast(m.content));
        allocator.free(recent);
    }

    const last_user_ms = app.store.getLastUserMsgMs();
    const last_episode = app.store.latestActiveObjectByKey(pid, "episode", "summary");
    const last_thought = app.store.latestActiveObjectByKey(pid, "self", "thought");

    return .{
        .identity = identity,
        .memory = memory,
        .candidates = candidates,
        .recent = recent,
        .now_ms = now_ms,
        .last_user_ms = last_user_ms,
        .last_episode = last_episode,
        .last_thought = last_thought,
    };
}

fn generateReply(
    allocator: std.mem.Allocator,
    app: *App,
    pid: i64,
    ctx: *const TurnContext,
    user_input: []const u8,
) ![]u8 {
    try app.store.insertMessage(allocator, pid, .user, user_input);

    app.cli.msg(.dbg, "injecting {d} memory items", .{ctx.memory.len});
    app.cli.msg(.dbg, "injecting {d} recent messages", .{ctx.recent.len});

    app.events.emitFmt(
        pid,
        .context_built,
        "chat",
        "memory={d} recent={d}",
        .{ ctx.memory.len, ctx.recent.len },
    );

    const model_msgs = try PromptBuilder.build(
        allocator,
        ctx.identity,
        ctx.memory,
        ctx.recent,
        user_input,
        ctx.now_ms,
        ctx.last_user_ms,
        ctx.last_episode,
        ctx.last_thought,
        app.ident.name,
        app.ident.persona_kernel,
        app.ident.prompts,
    );
    defer {
        if (model_msgs.len != 0 and model_msgs[0].role == .system) {
            allocator.free(@constCast(model_msgs[0].content));
        }
        allocator.free(model_msgs);
    }

    storeLastContext(app, model_msgs, ctx);

    app.cli.msg(.dbg, "prompt total messages: {d}", .{model_msgs.len});
    for (model_msgs, 0..) |msg, i| {
        app.cli.msg(.dbg, "[{d}] {s}: {s}", .{
            i,
            Types.roleToStr(msg.role),
            msg.content,
        });
    }

    const reply = try app.provider.chat(allocator, model_msgs, .{
        .model = app.conn.ollama_model,
        .temperature = app.ident.llm_chat.temperature,
        .max_tokens = app.ident.llm_chat.max_tokens,
    });
    errdefer allocator.free(reply);

    try app.store.insertMessage(allocator, pid, .assistant, reply);

    app.events.emitFmt(pid, .chat_completed, "chat", "len={d}", .{reply.len});

    return reply;
}

fn runReflection(
    allocator: std.mem.Allocator,
    app: *App,
    pid: i64,
    ctx: *const TurnContext,
    reply: []const u8,
    allow_memory_ops: bool,
) !void {
    const recent_for_reflection = try app.store.loadRecentMessages(
        allocator,
        pid,
        app.max_recent_messages,
    );
    defer {
        for (recent_for_reflection) |m| allocator.free(@constCast(m.content));
        allocator.free(recent_for_reflection);
    }

    const max_context_msgs = app.sys.max_context_msgs_reflector;
    const total_loaded = recent_for_reflection.len;

    const start_idx = if (total_loaded > max_context_msgs + 1)
        total_loaded - max_context_msgs - 1
    else
        0;

    const end_idx = if (total_loaded > 0) total_loaded - 1 else 0;

    const reflection_context = recent_for_reflection[start_idx..end_idx];

    const proposals = try Reflector.run(
        allocator,
        &app.provider,
        pid,
        ctx.identity,
        ctx.memory,
        reflection_context,
        reply,
        allow_memory_ops,
        app.cli,
        &app.events,
        app.ident.llm_reflection,
        app.ident.prompts,
        app.ident.name,
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
        const policy = app.ident.memory_policy;
        if (allow_memory_ops) {
            app.cli.msg(.hil, "[Governor evaluation]", .{});
            try Governor.apply(
                allocator,
                &app.store,
                pid,
                policy,
                proposals,
                app.cli,
                &app.events,
                .{
                    .rate_limit_ms = app.sys.rate_limit_ms,
                    .confidence_min = app.ident.confidence_min_governor,
                },
            );
        } else {
            app.cli.msg(
                .inf,
                "[Governor] skipped {d} proposal(s): no explicit intent",
                .{proposals.len},
            );
            for (proposals) |p| {
                app.events.emit(
                    pid,
                    .governor_blocked,
                    p.subject,
                    "no explicit intent",
                );
            }
        }
    }
}

fn storeLastContext(
    app: *App,
    model_msgs: []const Types.Message,
    ctx: *const TurnContext,
) void {
    const system_prompt = if (model_msgs.len > 0 and model_msgs[0].role == .system)
        model_msgs[0].content
    else
        "";

    const copy_len = @min(system_prompt.len, app.last_context_prompt_buf.len);
    @memcpy(app.last_context_prompt_buf[0..copy_len], system_prompt[0..copy_len]);

    app.last_context = .{
        .system_prompt = app.last_context_prompt_buf[0..copy_len],
        .memory_count = ctx.memory.len,
        .recent_count = ctx.recent.len,
        .max_recent_messages = app.max_recent_messages,
        .timestamp_ms = ctx.now_ms,
    };
}
