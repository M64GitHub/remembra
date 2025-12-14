//! Minimal HTTP client test for Zig 0.15 + Ollama.
//! This file serves as a reference for the Zig 0.15 HTTP client API.
//!
//! Run with: zig build run-http-test
//! Requires Ollama running: ollama serve
//!
//! Key patterns for Zig 0.15 HTTP:
//! - Use std.http.Client with fetch() method
//! - Use std.Io.Writer.Allocating for response body collection
//! - Use toArrayList() to get the response bytes

const std = @import("std");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    std.debug.print("Testing Zig 0.15 HTTP client with Ollama...\n", .{});

    const result = postToOllama(allocator) catch |err| {
        std.debug.print("Error: {}\n", .{err});
        return err;
    };
    defer allocator.free(result);

    std.debug.print("Response: {s}\n", .{result});
    std.debug.print("SUCCESS!\n", .{});
}

fn postToOllama(allocator: std.mem.Allocator) ![]u8 {
    var client: std.http.Client = .{ .allocator = allocator };
    defer client.deinit();

    const payload =
        \\{
        \\  "model": "llama3.2",
        \\  "messages": [
        \\    {"role": "user", "content": "Say hello in exactly 3 words."}
        \\  ],
        \\  "stream": false
        \\}
    ;

    var response_writer: std.Io.Writer.Allocating = .init(allocator);
    errdefer response_writer.deinit();

    const result = try client.fetch(.{
        .location = .{ .url = "http://127.0.0.1:11434/api/chat" },
        .method = .POST,
        .payload = payload,
        .extra_headers = &.{
            .{ .name = "Content-Type", .value = "application/json" },
        },
        .response_writer = &response_writer.writer,
    });

    if (result.status != .ok) {
        std.debug.print("HTTP error: {}\n", .{result.status});
        return error.HttpError;
    }

    var list = response_writer.toArrayList();
    defer list.deinit(allocator);
    return allocator.dupe(u8, list.items);
}
