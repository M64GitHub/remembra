const std = @import("std");
const version = @import("version.zig");
const Types = @import("Types.zig");
const Provider = @import("Provider.zig").Provider;
const MemoryStoreMock = @import("MemoryStoreMock.zig").MemoryStoreMock;
const PromptBuilder = @import("PromptBuilder.zig").PromptBuilder;
const Reflector = @import("Reflector.zig").Reflector;
const Governor = @import("Governor.zig").Governor;
const MemoryPolicy = @import("MemoryPolicy.zig").MemoryPolicy;
const Cli = @import("Cli.zig").Cli;
const EpisodeCompactor = @import("EpisodeCompactor.zig").EpisodeCompactor;
const InjectionGuard = @import("InjectionGuard.zig");
const Intent = @import("Intent.zig");
const IdleThinker = @import("IdleThinker.zig").IdleThinker;

fn readLine(file: std.fs.File, buf: []u8) !?[]u8 {
    var i: usize = 0;
    while (i < buf.len) {
        var byte: [1]u8 = undefined;
        const n = file.read(&byte) catch |err| {
            if (err == error.WouldBlock) continue;
            return err;
        };
        if (n == 0) {
            // EOF
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
    const A = gpa.allocator();

    var cli = try Cli.init(A);
    defer cli.deinit(A);
    cli.app_prefix = "REMEMBRA";
    cli.show_timestamp = false;
    cli.debug_level = 1;
    try cli.enableLogmode("REMEMBRA.log");

    cli.msg(.inf, "Starting up ...", .{});

    var provider = Provider.init(A);
    defer provider.deinit();

    var store = MemoryStoreMock.init(A);
    defer store.deinit();

    const policy = MemoryPolicy{};

    const stdin_file: std.fs.File = .{ .handle = std.posix.STDIN_FILENO };

    cli.msg(.hil, "{s} {s}", .{ version.name, version.version });
    cli.msg(.inf, "Phase 10: Re-entry context composer.", .{});
    cli.msg(
        .inf,
        "Commands: /mem add/ls/decay, /episode compact, /time advance, /idle run/tick, /quit",
        .{},
    );

    while (true) {
        cli.prompt("You: ", .{});

        var line_buf: [4096]u8 = undefined;
        const line_opt = try readLine(stdin_file, &line_buf);
        if (line_opt == null) break;

        const line = std.mem.trimRight(u8, line_opt.?, "\r\n");
        if (line.len == 0) continue;

        // Exit command
        if (std.mem.eql(u8, line, "/quit")) break;

        // Command: list memory
        if (std.mem.eql(u8, line, "/mem ls")) {
            const all = try store.loadAllMemoryItems(A);
            defer A.free(all);

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

        // Command: add memory
        if (std.mem.startsWith(u8, line, "/mem add ")) {
            const rest = line["/mem add ".len..];
            if (rest.len == 0) {
                cli.msg(.wrn, "Usage: /mem add <text>", .{});
                continue;
            }

            const id = try store.addMemoryGoverned(policy, .{
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

        // Command: simulate decay
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

            const mem = try store.loadMemoryItems(A, 50);
            defer A.free(mem);
            for (mem) |m| {
                cli.msg(.st2, "- [mem#{d}] {s}.{s}={s} (conf {d:.2})", .{
                    m.id, m.subject, m.predicate, m.object, m.confidence,
                });
            }
            continue;
        }

        // Command: advance simulated time
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

        // Command: run idle check
        if (std.mem.eql(u8, line, "/idle run")) {
            const now_ms = store.nowMs();
            try IdleThinker.maybeRun(
                A,
                &provider,
                &store,
                policy,
                cli,
                .{},
                now_ms,
            );
            continue;
        }

        // Command: tick idle (advance time + run)
        if (std.mem.startsWith(u8, line, "/idle tick ")) {
            const rest = line["/idle tick ".len..];
            const minutes = std.fmt.parseInt(i64, rest, 10) catch {
                cli.msg(.wrn, "Usage: /idle tick <minutes>", .{});
                continue;
            };
            store.advanceTimeMinutes(minutes);
            const now_ms = store.nowMs();
            try IdleThinker.maybeRun(
                A,
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

        // Command: episode compaction
        if (std.mem.eql(u8, line, "/episode compact")) {
            store.decayMemory(policy, store.nowMs());

            const ep_msgs = try store.loadMessagesSinceCutoff(A, 200);
            defer A.free(ep_msgs);

            if (ep_msgs.len == 0) {
                cli.msg(
                    .inf,
                    "No new messages since last episode cutoff (index {d}).",
                    .{store.getEpisodeCutoffIndex()},
                );
                continue;
            }

            const ep = try EpisodeCompactor.run(A, &provider, ep_msgs);
            defer {
                A.free(ep.title);
                A.free(ep.summary);
            }

            const combined = try std.fmt.allocPrint(
                A,
                "{s}\n{s}",
                .{ ep.title, ep.summary },
            );
            defer A.free(combined);

            const id = try store.addMemoryGoverned(policy, .{
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

        // Phase 7: Injection guard + intent classification
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

        // Normal user message - load context BEFORE inserting new message
        const identity = try store.loadIdentityCore(A);
        defer A.free(identity);

        const now_ms = store.nowMs();
        store.decayMemory(policy, now_ms);

        try IdleThinker.maybeRun(
            A,
            &provider,
            &store,
            policy,
            cli,
            .{},
            now_ms,
        );

        const memory = try store.loadMemoryItems(A, 20);
        defer A.free(memory);

        const recent = try store.loadRecentMessages(A, 24);
        defer A.free(recent);

        const last_user_ms = store.getLastUserMsgMs();

        const last_episode = store.latestActiveObjectByKey("episode", "summary");
        const last_thought = store.latestActiveObjectByKey("self", "thought");

        // NOW insert the user message (after loading context)
        try store.insertMessage(.user, line);

        cli.msg(.dbg, "injecting {d} memory items", .{memory.len});
        cli.msg(.dbg, "injecting {d} recent messages", .{recent.len});

        const model_msgs = try PromptBuilder.build(
            A,
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
                A.free(@constCast(model_msgs[0].content));
            }
            A.free(model_msgs);
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
            A,
            model_msgs,
            .{ .model = "mock", .temperature = 0.7, .max_tokens = 256 },
        );
        defer A.free(reply);

        try store.insertMessage(.assistant, reply);

        cli.msg(.rok, "{s}", .{reply});

        // --- Phase 4: Governor applies allowed proposals ---
        // Reload recent to include current user message for reflection
        const recent_for_reflection = try store.loadRecentMessages(A, 24);
        defer A.free(recent_for_reflection);

        const proposals = try Reflector.run(
            A,
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
                A.free(@constCast(p.subject));
                A.free(@constCast(p.predicate));
                A.free(@constCast(p.object));
            }
            A.free(proposals);
        }

        if (proposals.len != 0) {
            cli.msg(.hil, "[Governor evaluation]", .{});
            try Governor.apply(&store, policy, proposals, cli);
        }
    }
}
