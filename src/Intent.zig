const std = @import("std");

pub const MemoryIntent = enum {
    none,
    explicit_store,
};

/// Phase 7: intent must be explicit and local to THIS user message.
pub fn classifyMemoryIntent(user_text: []const u8) MemoryIntent {
    const patterns = [_][]const u8{
        "remember",
        "Remember",
        "please remember",
        "store this",
        "save this",
        "don't forget",
        "Do not forget",
    };

    for (patterns) |p| {
        if (std.mem.indexOf(u8, user_text, p) != null) return .explicit_store;
    }
    return .none;
}

test "Intent explicit_store" {
    try std.testing.expect(
        classifyMemoryIntent("please remember x") == .explicit_store,
    );
    try std.testing.expect(
        classifyMemoryIntent("Remember this") == .explicit_store,
    );
}

test "Intent none" {
    try std.testing.expect(classifyMemoryIntent("hello world") == .none);
}
