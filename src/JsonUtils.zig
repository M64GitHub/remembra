//! Utilities for parsing JSON from LLM responses.
//! LLMs often wrap JSON in markdown code blocks.

const std = @import("std");

/// Extracts JSON object from LLM response that may be wrapped in:
/// - Markdown code blocks: ```json {...} ``` or ``` {...} ```
/// - Plain text with embedded JSON object
/// Returns a slice into the original response (no allocation).
pub fn extractJsonObject(response: []const u8) []const u8 {
    // Try ```json ... ```
    if (std.mem.indexOf(u8, response, "```json")) |start| {
        const after_fence = start + 7;
        const content_start = skipWhitespace(response, after_fence);
        if (std.mem.indexOfPos(u8, response, content_start, "```")) |end| {
            return std.mem.trimRight(u8, response[content_start..end], " \n\r\t");
        }
    }
    // Try ``` ... ```
    if (std.mem.indexOf(u8, response, "```")) |start| {
        const after_fence = start + 3;
        const content_start = skipWhitespace(response, after_fence);
        if (std.mem.indexOfPos(u8, response, content_start, "```")) |end| {
            return std.mem.trimRight(u8, response[content_start..end], " \n\r\t");
        }
    }
    // Find JSON object by matching braces
    if (std.mem.indexOf(u8, response, "{")) |start| {
        var depth: i32 = 0;
        for (response[start..], 0..) |c, i| {
            if (c == '{') depth += 1;
            if (c == '}') depth -= 1;
            if (depth == 0) return response[start .. start + i + 1];
        }
    }
    return response;
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
