const std = @import("std");
const Types = @import("Types.zig");
const MemoryPolicy = @import("MemoryPolicy.zig").MemoryPolicy;
const EpisodeCompactor = @import("EpisodeCompactor.zig").EpisodeCompactor;
const Temporal = @import("Temporal.zig").Temporal;
const Cli = @import("Cli.zig").Cli;
const JsonUtils = @import("JsonUtils.zig");
const ConfigIdentity = @import("ConfigIdentity.zig");
const LlmParams = ConfigIdentity.LlmParams;
const PromptTemplates = ConfigIdentity.PromptTemplates;
const EventSystem = @import("EventSystem.zig").EventSystem;

pub const IdleThinker = struct {
    pub const Params = struct {
        idle_threshold_ms: i64 = 5 * 60 * 1000,
        min_msgs_for_compaction: usize = 6,
        min_ms_between_thoughts: i64 = 2 * 60 * 1000,
    };

    pub fn maybeRun(
        allocator: std.mem.Allocator,
        provider: anytype,
        store: anytype,
        persona_id: i64,
        policy: MemoryPolicy,
        cli: *Cli,
        events: *EventSystem,
        params: Params,
        now_ms: i64,
        llm_idle: LlmParams,
        llm_episode: LlmParams,
        conf_idle: f32,
        conf_episode: f32,
        prompts: PromptTemplates,
        ai_name: []const u8,
    ) !void {
        const last_user = store.getLastUserMsgMs();
        const gap = Temporal.gapMs(now_ms, last_user);

        if (gap < params.idle_threshold_ms) return;

        const last_think = store.getLastIdleThinkMs();
        if (shouldThink(now_ms, last_think, params.min_ms_between_thoughts)) {
            const thought = try generateThought(
                allocator,
                provider,
                store,
                persona_id,
                now_ms,
                llm_idle,
                prompts,
                ai_name,
                cli,
            );
            defer allocator.free(thought);

            _ = try store.addMemoryGoverned(allocator, persona_id, policy, .{
                .kind = .note,
                .subject = "self",
                .predicate = "thought",
                .object = thought,
                .confidence = conf_idle,
                .is_active = true,
            });

            store.setLastIdleThinkMs(now_ms);
            cli.msg(.inf, "Idle thinker: stored self.thought", .{});
            events.emit(persona_id, .thought_generated, "self", thought);
        }

        const new_count = store.countMessagesSinceCutoff(persona_id);
        if (new_count >= params.min_msgs_for_compaction) {
            cli.msg(
                .inf,
                "Idle thinker: closing chapter (new messages since cutoff: {d})",
                .{new_count},
            );

            const ep_msgs = try store.loadMessagesSinceCutoff(
                allocator,
                persona_id,
                400,
            );
            defer {
                for (ep_msgs) |m| allocator.free(@constCast(m.content));
                allocator.free(ep_msgs);
            }

            if (ep_msgs.len != 0) {
                const ep = try EpisodeCompactor.run(
                    allocator,
                    provider,
                    ep_msgs,
                    llm_episode,
                    prompts,
                    ai_name,
                    cli,
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

                _ = try store.addMemoryGoverned(
                    allocator,
                    persona_id,
                    policy,
                    .{
                        .kind = .note,
                        .subject = "episode",
                        .predicate = "summary",
                        .object = combined,
                        .confidence = conf_episode,
                        .is_active = true,
                    },
                );

                store.advanceEpisodeCutoffToEnd(persona_id);
                cli.msg(
                    .ok,
                    "Idle thinker: episode summary stored and cutoff advanced.",
                    .{},
                );
                events.emit(persona_id, .episode_compacted, "episode", ep.title);
            }
        }
    }

    pub fn shouldThink(
        now_ms: i64,
        last_think_ms: i64,
        min_between_ms: i64,
    ) bool {
        if (last_think_ms <= 0) return true;
        const d = now_ms - last_think_ms;
        return d >= min_between_ms;
    }

    fn generateThought(
        allocator: std.mem.Allocator,
        provider: anytype,
        store: anytype,
        persona_id: i64,
        now_ms: i64,
        llm_params: LlmParams,
        prompts: PromptTemplates,
        ai_name: []const u8,
        cli: *Cli,
    ) ![]u8 {
        const prompt = try buildThoughtPrompt(
            allocator,
            store,
            persona_id,
            now_ms,
            prompts.idle_thinker,
            ai_name,
        );
        defer allocator.free(prompt);

        const msgs = &[_]Types.Message{
            .{ .role = .system, .content = prompt, .created_at_ms = 0 },
            .{
                .role = .user,
                .content = prompts.idle_user_trigger,
                .created_at_ms = 0,
            },
        };

        const resp = try provider.chat(
            allocator,
            msgs,
            .{
                .model = "mock-idle",
                .temperature = llm_params.temperature,
                .max_tokens = llm_params.max_tokens,
            },
            cli,
        );
        defer allocator.free(resp.content);

        const extracted = JsonUtils.extractJsonObject(resp.content);
        return parseThoughtJson(allocator, extracted) catch {
            return allocator.dupe(u8, resp.content);
        };
    }

    fn buildThoughtPrompt(
        allocator: std.mem.Allocator,
        store: anytype,
        persona_id: i64,
        now_ms: i64,
        idle_template: []const u8,
        ai_name: []const u8,
    ) ![]u8 {
        var out: std.ArrayList(u8) = .empty;
        errdefer out.deinit(allocator);

        try out.writer(allocator).print(
            "You are the IDLE THINKER of {s}.\n",
            .{ai_name},
        );
        try out.appendSlice(allocator, idle_template);
        try out.appendSlice(allocator, "\n\n");

        const recent = try store.loadRecentMessages(allocator, persona_id, 6);
        defer {
            for (recent) |m| allocator.free(@constCast(m.content));
            allocator.free(recent);
        }

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
