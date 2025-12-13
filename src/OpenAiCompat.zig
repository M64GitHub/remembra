const std = @import("std");

/// Extracts choices[0].message.content from an OpenAI-like JSON string.
/// Returns an owned string (allocator-owned).
pub fn extractAssistantContent(allocator: std.mem.Allocator, json: []const u8) ![]u8 {
    var parsed = try std.json.parseFromSlice(std.json.Value, allocator, json, .{});
    defer parsed.deinit();

    if (parsed.value != .object) return error.InvalidJson;
    const root = parsed.value.object;

    const choices_v = root.get("choices") orelse return error.InvalidJson;
    if (choices_v != .array) return error.InvalidJson;
    if (choices_v.array.items.len == 0) return error.InvalidJson;

    const choice0 = choices_v.array.items[0];
    if (choice0 != .object) return error.InvalidJson;

    const msg_v = choice0.object.get("message") orelse return error.InvalidJson;
    if (msg_v != .object) return error.InvalidJson;

    const content_v = msg_v.object.get("content") orelse return error.InvalidJson;
    if (content_v != .string) return error.InvalidJson;

    return allocator.dupe(u8, content_v.string);
}

test "OpenAiCompat extracts content" {
    const A = std.testing.allocator;

    const sample =
        "{\"choices\":[{\"message\":{\"role\":\"assistant\",\"content\":\"hello\"}}]}";
    const s = try extractAssistantContent(A, sample);
    defer A.free(s);

    try std.testing.expectEqualStrings("hello", s);
}
