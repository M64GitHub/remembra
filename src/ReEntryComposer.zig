//! Re-entry context composer for rich re-entry prompts.

const std = @import("std");
const Temporal = @import("Temporal.zig").Temporal;

pub const ReEntryComposer = struct {
    pub const Params = struct {
        threshold_ms: i64 = 6 * 60 * 60 * 1000,
        max_episode_chars: usize = 420,
        max_thought_chars: usize = 200,
    };

    pub fn shouldTrigger(now_ms: i64, last_user_ms: i64, params: Params) bool {
        const gap = Temporal.gapMs(now_ms, last_user_ms);
        return gap >= params.threshold_ms;
    }

    pub fn buildFromParts(
        allocator: std.mem.Allocator,
        now_ms: i64,
        last_user_ms: i64,
        last_episode_summary: ?[]const u8,
        last_idle_thought: ?[]const u8,
        params: Params,
    ) !?[]u8 {
        if (!shouldTrigger(now_ms, last_user_ms, params)) return null;

        const gap = Temporal.gapMs(now_ms, last_user_ms);
        const gap_str = try Temporal.formatDuration(allocator, gap);
        defer allocator.free(gap_str);

        var out: std.ArrayList(u8) = .empty;
        errdefer out.deinit(allocator);

        try out.appendSlice(allocator, "RE-ENTRY CONTEXT\n");
        try out.writer(allocator).print("- user_gap={s}\n", .{gap_str});
        try out.appendSlice(
            allocator,
            "- instruction: Acknowledge the gap briefly and warmly, then continue.\n",
        );

        if (last_episode_summary) |episode| {
            try out.appendSlice(allocator, "- last_episode_summary:\n  ");
            try out.appendSlice(allocator, truncate(episode, params.max_episode_chars));
            try out.append(allocator, '\n');
        } else {
            try out.appendSlice(allocator, "- last_episode_summary: (none)\n");
        }

        if (last_idle_thought) |thought| {
            try out.appendSlice(allocator, "- last_idle_thought:\n  ");
            try out.appendSlice(allocator, truncate(thought, params.max_thought_chars));
            try out.append(allocator, '\n');
        } else {
            try out.appendSlice(allocator, "- last_idle_thought: (none)\n");
        }

        try out.append(allocator, '\n');
        return try out.toOwnedSlice(allocator);
    }

    fn truncate(s: []const u8, max: usize) []const u8 {
        if (s.len <= max) return s;
        if (max < 3) return s[0..max];
        return s[0 .. max - 3];
    }
};

test "ReEntryComposer shouldTrigger" {
    const params = ReEntryComposer.Params{ .threshold_ms = 1000 };
    try std.testing.expect(ReEntryComposer.shouldTrigger(5000, 0, params) == false);
    try std.testing.expect(ReEntryComposer.shouldTrigger(5000, 4500, params) == false);
    try std.testing.expect(ReEntryComposer.shouldTrigger(5000, 3000, params) == true);
}

test "ReEntryComposer builds with all parts" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const A = gpa.allocator();

    const params = ReEntryComposer.Params{ .threshold_ms = 1000 };
    const s_opt = try ReEntryComposer.buildFromParts(
        A,
        5000,
        3000,
        "Episode summary text",
        "Idle thought text",
        params,
    );
    try std.testing.expect(s_opt != null);

    const s = s_opt.?;
    defer A.free(s);

    try std.testing.expect(std.mem.indexOf(u8, s, "RE-ENTRY CONTEXT") != null);
    try std.testing.expect(std.mem.indexOf(u8, s, "Episode summary text") != null);
    try std.testing.expect(std.mem.indexOf(u8, s, "Idle thought text") != null);
}

test "ReEntryComposer returns null below threshold" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const A = gpa.allocator();

    const params = ReEntryComposer.Params{ .threshold_ms = 10000 };
    const s_opt = try ReEntryComposer.buildFromParts(
        A,
        5000,
        3000,
        "EP",
        "TH",
        params,
    );
    try std.testing.expect(s_opt == null);
}

test "ReEntryComposer handles null parts" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const A = gpa.allocator();

    const params = ReEntryComposer.Params{ .threshold_ms = 1000 };
    const s_opt = try ReEntryComposer.buildFromParts(
        A,
        5000,
        3000,
        null,
        null,
        params,
    );
    try std.testing.expect(s_opt != null);

    const s = s_opt.?;
    defer A.free(s);

    try std.testing.expect(std.mem.indexOf(u8, s, "(none)") != null);
}
