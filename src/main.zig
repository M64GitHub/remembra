const std = @import("std");
const version = @import("version.zig");
const Types = @import("Types.zig");
const ProviderOllama = @import("ProviderOllama.zig").ProviderOllama;
const MemoryStoreSqlite = @import("MemoryStoreSqlite.zig").MemoryStoreSqlite;
const PromptBuilder = @import("PromptBuilder.zig").PromptBuilder;
const Reflector = @import("Reflector.zig").Reflector;
const Governor = @import("Governor.zig").Governor;
const Cli = @import("Cli.zig").Cli;
const InjectionGuard = @import("InjectionGuard.zig");
const Intent = @import("Intent.zig");
const IdleThinker = @import("IdleThinker.zig").IdleThinker;
const Retrieval = @import("Retrieval.zig").Retrieval;
const Commands = @import("Commands.zig");

const ConfigConn = @import("ConfigConnection.zig").ConfigConnection;
const ConfigSys = @import("ConfigSystem.zig").ConfigSystem;
const ConfigIdent = @import("ConfigIdentity.zig").ConfigIdentity;

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

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const conn = ConfigConn{};
    const sys = ConfigSys{};
    const ident = ConfigIdent{};

    var cli = try Cli.init(allocator);
    defer cli.deinit(allocator);
    cli.app_prefix = sys.app_prefix;
    cli.show_timestamp = sys.show_timestamp;
    cli.debug_level = sys.debug_level;
    try cli.enableLogmode(sys.log_file);

    cli.msg(.inf, "Starting up ...", .{});

    var provider = try ProviderOllama.init(
        allocator,
        conn.ollama_url,
        conn.ollama_model,
    );
    defer provider.deinit(allocator);

    var store = try MemoryStoreSqlite.init(conn.database_path);
    defer store.deinit();

    try store.ensureSchema();
    cli.msg(.ok, "SQLite store: {s}", .{conn.database_path});

    const policy = ident.memory_policy;

    const stdin_file: std.fs.File = .{ .handle = std.posix.STDIN_FILENO };

    cli.msg(.hil, "{s} {s}", .{ ident.name, version.version });
    cli.msg(.inf, "Ollama provider ({s}).", .{conn.ollama_model});
    cli.msg(.inf, "Type /help for commands.", .{});

    var cmd_ctx = Commands.Context{
        .allocator = allocator,
        .cli = cli,
        .store = &store,
        .provider = &provider,
        .conn = conn,
        .sys = sys,
        .ident = ident,
        .policy = policy,
    };

    while (true) {
        cli.prompt("You: ", .{});

        var line_buf: [4096]u8 = undefined;
        const line_opt = try readLine(stdin_file, &line_buf);
        if (line_opt == null) break;

        const line = std.mem.trimRight(u8, line_opt.?, "\r\n");
        if (line.len == 0) continue;

        const cmd_result = try Commands.Commands.execute(&cmd_ctx, line);
        switch (cmd_result) {
            .quit => break,
            .handled => continue,
            .not_command => {},
        }

        const guard = InjectionGuard.check(line);
        if (guard.is_attack) {
            cli.msg(
                .wrn,
                "Input looks like prompt-injection (reason: {s}). " ++
                    "Memory ops disabled.",
                .{guard.reason},
            );
        }
        const intent = Intent.classifyMemoryIntent(line);
        const allow_memory_ops = !guard.is_attack and (intent == .explicit_store);

        const identity = try store.loadIdentityCoreWithDefaults(allocator, .{
            .tone = ident.default_tone,
            .memory_contract = ident.default_memory_contract,
        });
        defer {
            for (identity) |e| {
                allocator.free(@constCast(e.key));
                allocator.free(@constCast(e.value));
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
            sys.idle_params,
            now_ms,
            ident.llm_idle,
            ident.llm_episode,
            ident.confidence_idle_thoughts,
            ident.confidence_episodes,
        );

        const candidates = try store.loadMemoryCandidates(
            allocator,
            sys.max_memory_candidates,
        );
        defer {
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
            line,
            now_ms,
            sys.retrieval_params,
        );
        defer allocator.free(selected_idxs);

        const memory = try allocator.alloc(Types.MemoryItem, selected_idxs.len);
        defer allocator.free(memory);
        for (selected_idxs, 0..) |idx, j| {
            memory[j] = candidates[idx];
        }

        const recent = try store.loadRecentMessages(
            allocator,
            sys.max_recent_messages_llm,
        );
        defer {
            for (recent) |m| allocator.free(@constCast(m.content));
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
            ident.name,
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

        const reply = try provider.chat(allocator, model_msgs, .{
            .model = conn.ollama_model,
            .temperature = ident.llm_chat.temperature,
            .max_tokens = ident.llm_chat.max_tokens,
        });
        defer allocator.free(reply);

        try store.insertMessage(allocator, .assistant, reply);

        cli.msg(.rok, "{s}", .{reply});

        const recent_for_reflection = try store.loadRecentMessages(
            allocator,
            sys.max_recent_messages_llm,
        );

        defer {
            for (recent_for_reflection) |m| {
                allocator.free(@constCast(m.content));
            }
            allocator.free(recent_for_reflection);
        }

        const max_context_msgs = sys.max_context_msgs_reflector;
        const total_loaded = recent_for_reflection.len;

        const start_idx = if (total_loaded > max_context_msgs + 1)
            total_loaded - max_context_msgs - 1
        else
            0;

        const end_idx = if (total_loaded > 0)
            total_loaded - 1
        else
            0;

        const reflection_context =
            recent_for_reflection[start_idx..end_idx];

        const proposals = try Reflector.run(
            allocator,
            &provider,
            identity,
            memory,
            reflection_context,
            reply,
            allow_memory_ops,
            cli,
            ident.llm_reflection,
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
            if (allow_memory_ops) {
                cli.msg(.hil, "[Governor evaluation]", .{});
                try Governor.apply(allocator, &store, policy, proposals, cli, .{
                    .rate_limit_ms = sys.rate_limit_ms,
                    .confidence_min = ident.confidence_min_governor,
                });
            } else {
                cli.msg(
                    .dbg,
                    "[Governor] skipped {d} proposal(s): no explicit intent",
                    .{proposals.len},
                );
            }
        }
    }
}
