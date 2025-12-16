//! Utilities for parsing JSON from LLM responses.
//! LLMs often wrap JSON in markdown code blocks.

const std = @import("std");

/// Extracts JSON object from LLM response that may be wrapped in:
/// - Markdown code blocks: ```json {...} ``` or ``` {...} ```
/// - Plain text with embedded JSON object
/// Returns a slice into the original response (no allocation).
pub fn extractJsonObject(response: []const u8) []const u8 {
    if (std.mem.indexOf(u8, response, "```json")) |start| {
        const after_fence = start + 7;
        const content_start = skipWhitespace(response, after_fence);
        if (std.mem.indexOfPos(u8, response, content_start, "```")) |end| {
            return std.mem.trimRight(u8, response[content_start..end], " \n\r\t");
        }
    }
    if (std.mem.indexOf(u8, response, "```")) |start| {
        const after_fence = start + 3;
        const content_start = skipWhitespace(response, after_fence);
        if (std.mem.indexOfPos(u8, response, content_start, "```")) |end| {
            return std.mem.trimRight(u8, response[content_start..end], " \n\r\t");
        }
    }
    // Look for { "proposals" first (expected Reflector format)
    if (std.mem.indexOf(u8, response, "{ \"proposals\"")) |start| {
        return extractObjectFromPos(response, start);
    }
    if (std.mem.indexOf(u8, response, "{\"proposals\"")) |start| {
        return extractObjectFromPos(response, start);
    }

    // Fallback: find first JSON object by matching braces
    if (std.mem.indexOf(u8, response, "{")) |start| {
        return extractObjectFromPos(response, start);
    }
    return response;
}

fn extractObjectFromPos(response: []const u8, start: usize) []const u8 {
    var depth: i32 = 0;
    for (response[start..], 0..) |c, i| {
        if (c == '{') depth += 1;
        if (c == '}') depth -= 1;
        if (depth == 0) return response[start .. start + i + 1];
    }
    return response[start..];
}

fn skipWhitespace(s: []const u8, start: usize) usize {
    var i = start;
    while (i < s.len and
        (s[i] == '\n' or s[i] == ' ' or s[i] == '\r' or s[i] == '\t'))
    {
        i += 1;
    }
    return i;
}

/// Strips trailing commas from JSON (e.g., `,}` or `,]`).
/// LLMs often produce invalid JSON with trailing commas.
/// Returns allocated string that caller must free.
pub fn stripTrailingCommas(
    allocator: std.mem.Allocator,
    json: []const u8,
) ![]u8 {
    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(allocator);

    var i: usize = 0;
    while (i < json.len) {
        if (json[i] == ',') {
            // Look ahead past whitespace for ] or }
            var j = i + 1;
            while (j < json.len and isWhitespace(json[j])) j += 1;
            if (j < json.len and (json[j] == ']' or json[j] == '}')) {
                // Skip the comma, copy whitespace
                i += 1;
                continue;
            }
        }
        try out.append(allocator, json[i]);
        i += 1;
    }

    return out.toOwnedSlice(allocator);
}

fn isWhitespace(c: u8) bool {
    return c == ' ' or c == '\n' or c == '\r' or c == '\t';
}

test "extractJsonObject from markdown code block" {
    const input = "Here is the JSON:\n```json\n{\"foo\": 1}\n```\nDone.";
    const result = extractJsonObject(input);
    try std.testing.expectEqualStrings("{\"foo\": 1}", result);
}

test "extractJsonObject from plain code block" {
    const input = "```\n{\"bar\": 2}\n```";
    const result = extractJsonObject(input);
    try std.testing.expectEqualStrings("{\"bar\": 2}", result);
}

test "extractJsonObject from plain response" {
    const input = "{\"proposals\": []}";
    const result = extractJsonObject(input);
    try std.testing.expectEqualStrings("{\"proposals\": []}", result);
}

test "extractJsonObject with surrounding text" {
    const input = "Sure! Here is the result: {\"x\": 1} Hope that helps!";
    const result = extractJsonObject(input);
    try std.testing.expectEqualStrings("{\"x\": 1}", result);
}

test "extractJsonObject skips inline examples to find proposals" {
    const input =
        \\Example: { "action": "add", "x": 1 }
        \\Another: { "action": "update" }
        \\{ "proposals": [{"a": 1}] }
    ;
    const result = extractJsonObject(input);
    try std.testing.expectEqualStrings("{\"proposals\": [{\"a\": 1}]}", result);
}

test "stripTrailingCommas removes trailing commas" {
    const allocator = std.testing.allocator;

    const input = "{\"a\": 1,}";
    const result = try stripTrailingCommas(allocator, input);
    defer allocator.free(result);
    try std.testing.expectEqualStrings("{\"a\": 1}", result);
}

test "stripTrailingCommas handles arrays" {
    const allocator = std.testing.allocator;

    const input = "[1, 2, 3,]";
    const result = try stripTrailingCommas(allocator, input);
    defer allocator.free(result);
    try std.testing.expectEqualStrings("[1, 2, 3]", result);
}

test "stripTrailingCommas handles nested with whitespace" {
    const allocator = std.testing.allocator;

    const input = "{\"arr\": [1,\n  ],\n}";
    const result = try stripTrailingCommas(allocator, input);
    defer allocator.free(result);
    try std.testing.expectEqualStrings("{\"arr\": [1\n  ]\n}", result);
}
