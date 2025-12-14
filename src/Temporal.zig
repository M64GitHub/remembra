//! Temporal utilities for gap computation and duration formatting.

const std = @import("std");

pub const Temporal = struct {
    pub fn gapMs(now_ms: i64, last_ms: i64) i64 {
        if (last_ms <= 0) return 0;
        const d = now_ms - last_ms;
        return if (d < 0) 0 else d;
    }

    pub fn formatDuration(allocator: std.mem.Allocator, ms: i64) ![]u8 {
        var s: std.ArrayList(u8) = .empty;
        errdefer s.deinit(allocator);

        const sec: i64 = @divTrunc(ms, 1000);
        const min: i64 = @divTrunc(sec, 60);
        const hr: i64 = @divTrunc(min, 60);
        const day: i64 = @divTrunc(hr, 24);

        const rem_hr = hr - day * 24;
        const rem_min = min - hr * 60;

        if (day > 0) {
            try s.writer(allocator).print(
                "{d}d {d}h {d}m",
                .{ day, rem_hr, rem_min },
            );
        } else if (hr > 0) {
            try s.writer(allocator).print("{d}h {d}m", .{ hr, rem_min });
        } else {
            try s.writer(allocator).print("{d}m", .{min});
        }

        return s.toOwnedSlice(allocator);
    }
};

test "Temporal gap clamps negatives" {
    try std.testing.expectEqual(@as(i64, 0), Temporal.gapMs(1000, 2000));
}

test "Temporal gap returns zero for invalid last_ms" {
    try std.testing.expectEqual(@as(i64, 0), Temporal.gapMs(5000, 0));
    try std.testing.expectEqual(@as(i64, 0), Temporal.gapMs(5000, -100));
}

test "Temporal gap computes correctly" {
    try std.testing.expectEqual(@as(i64, 3000), Temporal.gapMs(5000, 2000));
}

test "Temporal formatting hours" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const s = try Temporal.formatDuration(allocator, 7 * 60 * 60 * 1000 + 2 * 60 * 1000);
    defer allocator.free(s);

    try std.testing.expectEqualStrings("7h 2m", s);
}

test "Temporal formatting days" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const s = try Temporal.formatDuration(allocator, 3 * 24 * 60 * 60 * 1000);
    defer allocator.free(s);

    try std.testing.expectEqualStrings("3d 0h 0m", s);
}

test "Temporal formatting minutes only" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const s = try Temporal.formatDuration(allocator, 45 * 60 * 1000);
    defer allocator.free(s);

    try std.testing.expectEqualStrings("45m", s);
}
