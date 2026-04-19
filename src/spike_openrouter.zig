//! Spike: verify that std.http.Client.request streams HTTPS SSE chunks
//! incrementally (not buffered until EOF). Gate for ProviderOpenRouter.
//!
//! Usage: OPENROUTER_API_KEY=sk-... zig build spike-openrouter
//!
//! Prints each received line with a wall-clock ms offset. If first-line
//! and last-line timestamps are close, the client is buffering and we
//! must fall back to raw TCP + std.crypto.tls.Client.

const std = @import("std");

const BASE_URL = "https://openrouter.ai/api/v1/chat/completions";
const MODEL = "openai/gpt-4o-mini";

const PAYLOAD =
    \\{"model":"anthropic/claude-3.5-haiku","stream":true,
    \\"messages":[{"role":"user","content":
    \\"Write a short poem about streams"}],
    \\"max_tokens":100}
;

pub fn main() !void {
    var gpa: std.heap.GeneralPurposeAllocator(.{}) = .init;
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const api_key = std.process.getEnvVarOwned(
        allocator,
        "OPENROUTER_API_KEY",
    ) catch {
        std.debug.print(
            "error: OPENROUTER_API_KEY env var is not set.\n",
            .{},
        );
        return error.MissingApiKey;
    };
    defer allocator.free(api_key);

    const auth = try std.fmt.allocPrint(
        allocator,
        "Bearer {s}",
        .{api_key},
    );
    defer allocator.free(auth);

    const t0 = std.time.nanoTimestamp();

    var client: std.http.Client = .{ .allocator = allocator };
    defer client.deinit();

    const uri = try std.Uri.parse(BASE_URL);

    const payload = try allocator.dupe(u8, PAYLOAD);
    defer allocator.free(payload);

    var req = try client.request(.POST, uri, .{
        .headers = .{
            .authorization = .{ .override = auth },
            .content_type = .{ .override = "application/json" },
        },
        .extra_headers = &.{
            .{ .name = "HTTP-Referer", .value = "http://127.0.0.1" },
            .{ .name = "X-Title", .value = "REMEMBRA-spike" },
        },
        .keep_alive = false,
    });
    defer req.deinit();

    req.transfer_encoding = .{ .content_length = payload.len };
    try req.sendBodyComplete(payload);

    var redirect_buf: [1024]u8 = undefined;
    var response = try req.receiveHead(&redirect_buf);

    const status = response.head.status;
    std.debug.print(
        "[{d} ms] status={s}\n",
        .{ elapsedMs(t0), @tagName(status) },
    );
    if (@intFromEnum(status) >= 400) {
        std.debug.print(
            "error: non-2xx status, aborting\n",
            .{},
        );
        return error.HttpError;
    }

    var transfer_buf: [8192]u8 = undefined;
    const reader = response.reader(&transfer_buf);

    var line_buf: [32768]u8 = undefined;
    var chunk_count: u32 = 0;
    var first_chunk_ms: i64 = 0;
    var last_chunk_ms: i64 = 0;

    while (true) {
        const n = readLine(reader, &line_buf) catch |err| {
            if (err == error.EndOfStream) break;
            std.debug.print("read error: {}\n", .{err});
            return err;
        };

        const line = line_buf[0..n];
        const ms = elapsedMs(t0);

        if (line.len == 0) continue;
        if (line[0] == ':') continue;

        if (std.mem.startsWith(u8, line, "data: ")) {
            const body = line["data: ".len..];
            chunk_count += 1;
            if (chunk_count == 1) first_chunk_ms = ms;
            last_chunk_ms = ms;
            std.debug.print("[{d} ms] data: {s}\n", .{ ms, body });
            if (std.mem.eql(u8, body, "[DONE]")) break;
        } else {
            std.debug.print(
                "[{d} ms] <raw> {s}\n",
                .{ ms, line },
            );
        }
    }

    const total_ms = elapsedMs(t0);
    const spread_ms = last_chunk_ms - first_chunk_ms;

    std.debug.print("\n--- spike summary ---\n", .{});
    std.debug.print("chunks:        {d}\n", .{chunk_count});
    std.debug.print("first chunk:   {d} ms\n", .{first_chunk_ms});
    std.debug.print("last chunk:    {d} ms\n", .{last_chunk_ms});
    std.debug.print("first->last:   {d} ms\n", .{spread_ms});
    std.debug.print("total:         {d} ms\n", .{total_ms});

    if (spread_ms < 100) {
        std.debug.print(
            "\nVERDICT: chunks arrived in <100ms spread -- client " ++
                "may be buffering. Investigate raw TCP+TLS fallback.\n",
            .{},
        );
    } else {
        std.debug.print(
            "\nVERDICT: incremental streaming confirmed " ++
                "(first->last spread {d} ms). Safe to proceed.\n",
            .{spread_ms},
        );
    }
}

fn elapsedMs(t0: i128) i64 {
    const now = std.time.nanoTimestamp();
    return @intCast(@divFloor(now - t0, 1_000_000));
}

fn readLine(reader: *std.Io.Reader, buf: []u8) !usize {
    var pos: usize = 0;
    while (pos < buf.len) {
        const byte_slice = reader.take(1) catch |err| {
            if (pos == 0) return err;
            break;
        };
        const byte = byte_slice[0];
        if (byte == '\n') {
            if (pos > 0 and buf[pos - 1] == '\r') return pos - 1;
            return pos;
        }
        buf[pos] = byte;
        pos += 1;
    }
    return pos;
}
