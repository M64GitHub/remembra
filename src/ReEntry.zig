//! Re-entry protocol for handling time gaps between user interactions.

const std = @import("std");
const Temporal = @import("Temporal.zig").Temporal;

pub const ReEntry = struct {
    pub const Params = struct {
        threshold_ms: i64 = 6 * 60 * 60 * 1000,
    };

    pub fn shouldReEnter(now_ms: i64, last_user_ms: i64, params: Params) bool {
        const gap = Temporal.gapMs(now_ms, last_user_ms);
        return gap >= params.threshold_ms;
    }

    pub fn buildNote(
        allocator: std.mem.Allocator,
        now_ms: i64,
        last_user_ms: i64,
    ) ![]u8 {
        const gap = Temporal.gapMs(now_ms, last_user_ms);
        const d = try Temporal.formatDuration(allocator, gap);
        defer allocator.free(d);

        return std.fmt.allocPrint(
            allocator,
            "RE-ENTRY: The user was away for {s}. " ++
                "Acknowledge the gap naturally, then continue normally.\n",
            .{d},
        );
    }
};

test "ReEntry triggers after threshold" {
    const params = ReEntry.Params{ .threshold_ms = 1000 };
    try std.testing.expect(ReEntry.shouldReEnter(5000, 0, params) == false);
    try std.testing.expect(ReEntry.shouldReEnter(5000, 4500, params) == false);
    try std.testing.expect(ReEntry.shouldReEnter(5000, 3000, params) == true);
}

test "ReEntry does not trigger below threshold" {
    const params = ReEntry.Params{ .threshold_ms = 6 * 60 * 60 * 1000 };
    const now: i64 = 10000000;
    const last = now - (5 * 60 * 60 * 1000);
    try std.testing.expect(ReEntry.shouldReEnter(now, last, params) == false);
}

test "ReEntry builds note correctly" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const A = gpa.allocator();

    const now: i64 = 24 * 60 * 60 * 1000;
    const last: i64 = 0;
    const note = try ReEntry.buildNote(A, now, last);
    defer A.free(note);

    try std.testing.expect(std.mem.indexOf(u8, note, "RE-ENTRY") != null);
}
