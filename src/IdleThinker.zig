const std = @import("std");
const Types = @import("Types.zig");
const Provider = @import("Provider.zig").Provider;
const MemoryStoreMock = @import("MemoryStoreMock.zig").MemoryStoreMock;
const MemoryPolicy = @import("MemoryPolicy.zig").MemoryPolicy;
const EpisodeCompactor = @import("EpisodeCompactor.zig").EpisodeCompactor;
const Temporal = @import("Temporal.zig").Temporal;
const Cli = @import("Cli.zig").Cli;

pub const IdleThinker = struct {
    pub const Params = struct {
        idle_threshold_ms: i64 = 5 * 60 * 1000,
        min_msgs_for_compaction: usize = 6,
        min_ms_between_thoughts: i64 = 2 * 60 * 1000,
    };

    pub fn maybeRun(
        allocator: std.mem.Allocator,
        provider: *Provider,
        store: *MemoryStoreMock,
        policy: MemoryPolicy,
        cli: *Cli,
        params: Params,
        now_ms: i64,
    ) !void {
        const last_user = store.getLastUserMsgMs();
        const gap = Temporal.gapMs(now_ms, last_user);

        if (gap < params.idle_threshold_ms) return;

        const last_think = store.getLastIdleThinkMs();
        if (shouldThink(now_ms, last_think, params.min_ms_between_thoughts)) {
            const thought = try generateThought(allocator, provider, store, now_ms);
            defer allocator.free(thought);

            _ = try store.addMemoryGoverned(allocator, policy, .{
                .kind = .note,
                .subject = "self",
                .predicate = "thought",
                .object = thought,
                .confidence = 0.55,
                .is_active = true,
            });

            store.setLastIdleThinkMs(now_ms);
            cli.msg(.inf, "Idle thinker: stored self.thought", .{});
        }

        const new_count = store.countMessagesSinceCutoff();
        if (new_count >= params.min_msgs_for_compaction) {
            cli.msg(
                .inf,
                "Idle thinker: closing chapter (new messages since cutoff: {d})",
                .{new_count},
            );

            const ep_msgs = try store.loadMessagesSinceCutoff(allocator, 400);
            defer allocator.free(ep_msgs);

            if (ep_msgs.len != 0) {
                const ep = try EpisodeCompactor.run(allocator, provider, ep_msgs);
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

                _ = try store.addMemoryGoverned(allocator, policy, .{
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
                    "Idle thinker: episode summary stored and cutoff advanced.",
                    .{},
                );
            }
        }
    }

    pub fn shouldThink(now_ms: i64, last_think_ms: i64, min_between_ms: i64) bool {
        if (last_think_ms <= 0) return true;
        const d = now_ms - last_think_ms;
        return d >= min_between_ms;
    }

    fn generateThought(
        allocator: std.mem.Allocator,
        provider: *Provider,
        store: *MemoryStoreMock,
        now_ms: i64,
    ) ![]u8 {
        const prompt = try buildThoughtPrompt(allocator, store, now_ms);
        defer allocator.free(prompt);

        const msgs = &[_]Types.Message{
            .{ .role = .system, .content = prompt, .created_at_ms = 0 },
        };

        const json = try provider.chat(allocator, msgs, .{
            .model = "mock-idle",
            .temperature = 0.4,
            .max_tokens = 160,
        });
        defer allocator.free(json);

        return parseThoughtJson(allocator, json);
    }

    fn buildThoughtPrompt(
        allocator: std.mem.Allocator,
        store: *MemoryStoreMock,
        now_ms: i64,
    ) ![]u8 {
        var out: std.ArrayList(u8) = .empty;
        errdefer out.deinit(allocator);

        try out.appendSlice(
            allocator,
            "IDLE_MONOLOGUE\n" ++
                "You are the IDLE THINKER of REMEMBRA.\n" ++
                "Generate ONE short inner thought about continuity.\n" ++
                "Output JSON ONLY.\n" ++
                "Schema: { \"thought\": \"...\" }\n\n",
        );

        const recent = try store.loadRecentMessages(allocator, 6);
        defer allocator.free(recent);

        try out.writer(allocator).print("now_ms={d}\nrecent:\n", .{now_ms});
        for (recent) |m| {
            try out.writer(allocator).print(
                "{s}: {s}\n",
                .{ Types.roleToStr(m.role), m.content },
            );
        }

        return out.toOwnedSlice(allocator);
    }

    fn parseThoughtJson(allocator: std.mem.Allocator, json: []const u8) ![]u8 {
        var parsed = try std.json.parseFromSlice(
            std.json.Value,
            allocator,
            json,
            .{},
        );
        defer parsed.deinit();

        if (parsed.value != .object) return error.InvalidIdleJson;
        const root = parsed.value.object;
        const t = root.get("thought") orelse return error.InvalidIdleJson;
        if (t != .string) return error.InvalidIdleJson;

        return allocator.dupe(u8, t.string);
    }
};

test "IdleThinker shouldThink basic" {
    try std.testing.expect(IdleThinker.shouldThink(1000, 0, 100) == true);
    try std.testing.expect(IdleThinker.shouldThink(1000, 950, 100) == false);
    try std.testing.expect(IdleThinker.shouldThink(1000, 900, 100) == true);
}

test "IdleThinker shouldThink negative last_think" {
    try std.testing.expect(IdleThinker.shouldThink(1000, -100, 100) == true);
}
