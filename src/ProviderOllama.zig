//! Ollama provider - HTTP client for Ollama's native /api/chat endpoint.
//! Supports both blocking (stream=false) and streaming (stream=true) modes.

const std = @import("std");
const Types = @import("Types.zig");
const Cli = @import("Cli.zig").Cli;

pub const ProviderOllama = struct {
    base_url: []u8,
    model: []u8,

    pub fn init(
        allocator: std.mem.Allocator,
        base_url: []const u8,
        model: []const u8,
    ) !ProviderOllama {
        return .{
            .base_url = try allocator.dupe(u8, base_url),
            .model = try allocator.dupe(u8, model),
        };
    }

    pub fn deinit(self: *ProviderOllama, allocator: std.mem.Allocator) void {
        allocator.free(self.base_url);
        allocator.free(self.model);
    }

    pub fn chat(
        self: *ProviderOllama,
        allocator: std.mem.Allocator,
        msgs: []const Types.Message,
        params: Types.ChatParams,
        cli: *Cli,
    ) !Types.ChatResponse {
        const url = try std.fmt.allocPrint(
            allocator,
            "{s}/api/chat",
            .{trimTrailingSlash(self.base_url)},
        );
        defer allocator.free(url);

        const payload =
            try buildRequestJson(allocator, self.model, msgs, params);
        defer allocator.free(payload);

        cli.msg(.dbg, "PAYLOAD:\n{s}", .{payload});

        const response = try httpPost(allocator, url, payload);
        defer allocator.free(response);
        cli.msg(.dbg, "RESPONSE:\n{s}", .{response});

        return parseResponse(allocator, response);
    }

    pub fn chatStream(
        self: *ProviderOllama,
        allocator: std.mem.Allocator,
        msgs: []const Types.Message,
        params: Types.ChatParams,
        cli: *Cli,
        writer: anytype,
    ) !Types.StreamResult {
        const url = try std.fmt.allocPrint(
            allocator,
            "{s}/api/chat",
            .{trimTrailingSlash(self.base_url)},
        );
        defer allocator.free(url);

        const payload = try buildStreamingRequestJson(
            allocator,
            self.model,
            msgs,
            params,
        );
        defer allocator.free(payload);

        cli.msg(.dbg, "STREAM PAYLOAD:\n{s}", .{payload});

        return httpPostStream(allocator, url, payload, cli, writer);
    }

    fn httpPostStream(
        allocator: std.mem.Allocator,
        url: []const u8,
        payload: []const u8,
        cli: *Cli,
        output_writer: anytype,
    ) !Types.StreamResult {
        const uri = std.Uri.parse(url) catch return error.InvalidUrl;

        const host = uri.host orelse return error.InvalidUrl;
        const port: u16 = uri.port orelse 80;

        const stream = std.net.tcpConnectToHost(
            allocator,
            host.percent_encoded,
            port,
        ) catch |err| {
            cli.msg(.err, "TCP connect error: {}", .{err});
            return error.OllamaHttpError;
        };
        defer stream.close();

        var write_buf: [4096]u8 = undefined;
        var buf_writer = stream.writer(&write_buf);
        var writer = &buf_writer.interface;

        var hdr_buf: [1024]u8 = undefined;
        const header = std.fmt.bufPrint(
            &hdr_buf,
            "POST {s} HTTP/1.1\r\n" ++
                "Host: {s}\r\n" ++
                "Content-Type: application/json\r\n" ++
                "Content-Length: {d}\r\n" ++
                "Connection: close\r\n" ++
                "\r\n",
            .{ uri.path.percent_encoded, host.percent_encoded, payload.len },
        ) catch return error.InvalidUrl;

        try writer.writeAll(header);
        try writer.writeAll(payload);
        try writer.flush();

        var read_buf: [8192]u8 = undefined;
        var buf_reader = stream.reader(&read_buf);

        var header_done = false;
        var line_buf: [16384]u8 = undefined;

        const reader_iface = buf_reader.interface();

        while (!header_done) {
            const line_len = readLine(reader_iface, &line_buf) catch break;
            if (line_len == 0) {
                header_done = true;
            }
        }

        var stats: Types.StreamStats = .{};
        var content_buf: std.ArrayListUnmanaged(u8) = .empty;
        errdefer content_buf.deinit(allocator);

        while (true) {
            const line_len = readLine(reader_iface, &line_buf) catch |err| {
                if (err == error.EndOfStream) break;
                return err;
            };

            if (line_len == 0) continue;

            const line = line_buf[0..line_len];

            // Skip chunked transfer encoding size lines (hex digits only)
            const is_chunk_size = blk: {
                if (line.len > 8) break :blk false;
                for (line) |c| {
                    if (!std.ascii.isHex(c)) break :blk false;
                }
                break :blk true;
            };
            if (is_chunk_size) continue;

            const chunk = parseStreamChunk(allocator, line) catch |err| {
                cli.msg(.wrn, "Failed to parse chunk: {}", .{err});
                continue;
            };
            defer allocator.free(chunk.content);
            defer allocator.free(chunk.thinking);

            // Accumulate content for storage
            if (chunk.content.len > 0) {
                try content_buf.appendSlice(allocator, chunk.content);
            }

            writeSseEvent(output_writer, chunk) catch |err| {
                cli.msg(.wrn, "Failed to write SSE: {}", .{err});
                return error.WriteError;
            };
            output_writer.flush() catch {};

            if (chunk.done) {
                stats.prompt_tokens = chunk.prompt_tokens;
                stats.completion_tokens = chunk.completion_tokens;
                stats.eval_duration_ns = chunk.eval_duration_ns;
                break;
            }
        }

        return .{
            .stats = stats,
            .content = try content_buf.toOwnedSlice(allocator),
        };
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
                if (pos > 0 and buf[pos - 1] == '\r') {
                    return pos - 1;
                }
                return pos;
            }
            buf[pos] = byte;
            pos += 1;
        }
        return pos;
    }

    fn parseStreamChunk(
        allocator: std.mem.Allocator,
        line: []const u8,
    ) !Types.StreamChunk {
        var parsed = std.json.parseFromSlice(
            std.json.Value,
            allocator,
            line,
            .{},
        ) catch return error.OllamaInvalidJson;
        defer parsed.deinit();

        const root = parsed.value;
        if (root != .object) return error.OllamaInvalidJson;

        const done = blk: {
            const done_val = root.object.get("done") orelse break :blk false;
            if (done_val != .bool) break :blk false;
            break :blk done_val.bool;
        };

        var content_str: []const u8 = "";
        var thinking_str: []const u8 = "";
        if (root.object.get("message")) |msg| {
            if (msg == .object) {
                if (msg.object.get("content")) |c| {
                    if (c == .string) content_str = c.string;
                }
                if (msg.object.get("thinking")) |t| {
                    if (t == .string) thinking_str = t.string;
                }
            }
        }
        const content = try allocator.dupe(u8, content_str);
        errdefer allocator.free(content);
        const thinking = try allocator.dupe(u8, thinking_str);

        return .{
            .content = content,
            .thinking = thinking,
            .done = done,
            .prompt_tokens = extractOptionalInt(root.object, "prompt_eval_count"),
            .completion_tokens = extractOptionalInt(root.object, "eval_count"),
            .eval_duration_ns = extractOptionalInt64(root.object, "eval_duration"),
        };
    }

    fn writeSseEvent(writer: anytype, chunk: Types.StreamChunk) !void {
        try writer.writeAll("data: {\"content\":\"");
        try writeJsonEscaped(writer, chunk.content);
        try writer.writeAll("\",\"thinking\":\"");
        try writeJsonEscaped(writer, chunk.thinking);
        try writer.writeAll("\",\"done\":");
        if (chunk.done) {
            try writer.writeAll("true");
            if (chunk.prompt_tokens) |pt| {
                try writer.print(",\"prompt_tokens\":{d}", .{pt});
            }
            if (chunk.completion_tokens) |ct| {
                try writer.print(",\"completion_tokens\":{d}", .{ct});
            }
            if (chunk.eval_duration_ns) |ns| {
                const ms = @divFloor(ns, 1_000_000);
                try writer.print(",\"eval_duration_ms\":{d}", .{ms});
            }
        } else {
            try writer.writeAll("false");
        }
        try writer.writeAll("}\n\n");
    }

    fn writeJsonEscaped(writer: anytype, s: []const u8) !void {
        for (s) |c| {
            switch (c) {
                '\\' => try writer.writeAll("\\\\"),
                '"' => try writer.writeAll("\\\""),
                '\n' => try writer.writeAll("\\n"),
                '\r' => try writer.writeAll("\\r"),
                '\t' => try writer.writeAll("\\t"),
                else => try writer.writeByte(c),
            }
        }
    }

    fn buildStreamingRequestJson(
        allocator: std.mem.Allocator,
        model: []const u8,
        msgs: []const Types.Message,
        params: Types.ChatParams,
    ) ![]u8 {
        var out: std.ArrayListUnmanaged(u8) = .empty;
        errdefer out.deinit(allocator);

        try out.appendSlice(allocator, "{\"model\":\"");
        try appendJsonEscaped(&out, allocator, model);
        try out.appendSlice(allocator, "\",\"messages\":[");

        for (msgs, 0..) |m, i| {
            if (i != 0) try out.append(allocator, ',');
            try out.appendSlice(allocator, "{\"role\":\"");
            try out.appendSlice(allocator, Types.roleToStr(m.role));
            try out.appendSlice(allocator, "\",\"content\":\"");
            try appendJsonEscaped(&out, allocator, m.content);
            try out.appendSlice(allocator, "\"}");
        }

        try out.appendSlice(allocator, "],\"stream\":true");

        try out.appendSlice(allocator, ",\"options\":{");
        try out.writer(allocator).print(
            "\"temperature\":{d:.2}",
            .{params.temperature},
        );
        try out.appendSlice(allocator, "}}");

        return out.toOwnedSlice(allocator);
    }

    fn trimTrailingSlash(s: []const u8) []const u8 {
        if (s.len == 0) return s;
        if (s[s.len - 1] == '/') return s[0 .. s.len - 1];
        return s;
    }

    fn httpPost(
        allocator: std.mem.Allocator,
        url: []const u8,
        payload: []const u8,
    ) ![]u8 {
        var client: std.http.Client = .{ .allocator = allocator };
        defer client.deinit();

        var response_writer: std.Io.Writer.Allocating = .init(allocator);
        errdefer response_writer.deinit();

        const result = try client.fetch(.{
            .location = .{ .url = url },
            .method = .POST,
            .payload = payload,
            .extra_headers = &.{
                .{ .name = "Content-Type", .value = "application/json" },
            },
            .response_writer = &response_writer.writer,
        });

        if (result.status != .ok) {
            return error.OllamaHttpError;
        }

        var list = response_writer.toArrayList();
        defer list.deinit(allocator);
        return allocator.dupe(u8, list.items);
    }

    fn buildRequestJson(
        allocator: std.mem.Allocator,
        model: []const u8,
        msgs: []const Types.Message,
        params: Types.ChatParams,
    ) ![]u8 {
        var out: std.ArrayListUnmanaged(u8) = .empty;
        errdefer out.deinit(allocator);

        try out.appendSlice(allocator, "{\"model\":\"");
        try appendJsonEscaped(&out, allocator, model);
        try out.appendSlice(allocator, "\",\"messages\":[");

        for (msgs, 0..) |m, i| {
            if (i != 0) try out.append(allocator, ',');
            try out.appendSlice(allocator, "{\"role\":\"");
            try out.appendSlice(allocator, Types.roleToStr(m.role));
            try out.appendSlice(allocator, "\",\"content\":\"");
            try appendJsonEscaped(&out, allocator, m.content);
            try out.appendSlice(allocator, "\"}");
        }

        try out.appendSlice(allocator, "],\"stream\":false");

        try out.appendSlice(allocator, ",\"options\":{");
        try out.writer(allocator).print(
            "\"temperature\":{d:.2}",
            .{params.temperature},
        );
        try out.appendSlice(allocator, "}}");

        return out.toOwnedSlice(allocator);
    }

    fn appendJsonEscaped(
        out: *std.ArrayListUnmanaged(u8),
        allocator: std.mem.Allocator,
        s: []const u8,
    ) !void {
        for (s) |c| {
            switch (c) {
                '\\' => try out.appendSlice(allocator, "\\\\"),
                '"' => try out.appendSlice(allocator, "\\\""),
                '\n' => try out.appendSlice(allocator, "\\n"),
                '\r' => try out.appendSlice(allocator, "\\r"),
                '\t' => try out.appendSlice(allocator, "\\t"),
                else => try out.append(allocator, c),
            }
        }
    }

    fn parseResponse(
        allocator: std.mem.Allocator,
        json: []const u8,
    ) !Types.ChatResponse {
        var parsed = std.json.parseFromSlice(
            std.json.Value,
            allocator,
            json,
            .{},
        ) catch return error.OllamaInvalidJson;
        defer parsed.deinit();

        const root = parsed.value;
        if (root != .object) return error.OllamaInvalidJson;

        const msg = root.object.get("message") orelse
            return error.OllamaInvalidJson;
        if (msg != .object) return error.OllamaInvalidJson;

        const content = msg.object.get("content") orelse
            return error.OllamaInvalidJson;
        if (content != .string) return error.OllamaInvalidJson;

        const thinking = try extractOptionalString(
            allocator,
            msg.object,
            "thinking",
        );

        const prompt_tokens = extractOptionalInt(root.object, "prompt_eval_count");
        const completion_tokens = extractOptionalInt(root.object, "eval_count");
        const eval_duration = extractOptionalInt64(root.object, "eval_duration");

        return .{
            .content = try allocator.dupe(u8, content.string),
            .thinking = thinking,
            .prompt_tokens = prompt_tokens,
            .completion_tokens = completion_tokens,
            .eval_duration_ns = eval_duration,
        };
    }

    fn extractOptionalInt(
        obj: std.json.ObjectMap,
        key: []const u8,
    ) ?u32 {
        const val = obj.get(key) orelse return null;
        if (val != .integer) return null;
        if (val.integer < 0 or val.integer > std.math.maxInt(u32))
            return null;
        return @intCast(val.integer);
    }

    fn extractOptionalInt64(
        obj: std.json.ObjectMap,
        key: []const u8,
    ) ?i64 {
        const val = obj.get(key) orelse return null;
        if (val != .integer) return null;
        return val.integer;
    }

    fn extractOptionalString(
        allocator: std.mem.Allocator,
        obj: std.json.ObjectMap,
        key: []const u8,
    ) !?[]const u8 {
        const val = obj.get(key) orelse return null;
        if (val != .string) return null;
        return try allocator.dupe(u8, val.string);
    }
};

pub const OllamaModel = struct {
    name: []const u8,
    size: i64,
    digest: []const u8,
    modified_at: []const u8,
};

pub fn httpGet(allocator: std.mem.Allocator, url: []const u8) ![]u8 {
    var client: std.http.Client = .{ .allocator = allocator };
    defer client.deinit();

    var response_writer: std.Io.Writer.Allocating = .init(allocator);
    errdefer response_writer.deinit();

    const result = client.fetch(.{
        .location = .{ .url = url },
        .method = .GET,
        .response_writer = &response_writer.writer,
    }) catch return error.OllamaHttpError;

    if (result.status != .ok) {
        return error.OllamaHttpError;
    }

    var list = response_writer.toArrayList();
    defer list.deinit(allocator);
    return allocator.dupe(u8, list.items);
}

fn trimUrl(s: []const u8) []const u8 {
    if (s.len == 0) return s;
    if (s[s.len - 1] == '/') return s[0 .. s.len - 1];
    return s;
}

pub fn discoverModels(
    allocator: std.mem.Allocator,
    base_url: []const u8,
) ![]OllamaModel {
    const url = try std.fmt.allocPrint(
        allocator,
        "{s}/api/tags",
        .{trimUrl(base_url)},
    );
    defer allocator.free(url);

    const response = httpGet(allocator, url) catch {
        return allocator.alloc(OllamaModel, 0);
    };
    defer allocator.free(response);

    return parseTagsResponse(allocator, response);
}

fn parseTagsResponse(
    allocator: std.mem.Allocator,
    json: []const u8,
) ![]OllamaModel {
    var parsed = std.json.parseFromSlice(
        std.json.Value,
        allocator,
        json,
        .{},
    ) catch return allocator.alloc(OllamaModel, 0);
    defer parsed.deinit();

    const root = parsed.value;
    if (root != .object) return allocator.alloc(OllamaModel, 0);

    const models_val = root.object.get("models") orelse
        return allocator.alloc(OllamaModel, 0);
    if (models_val != .array) return allocator.alloc(OllamaModel, 0);

    var out: std.ArrayList(OllamaModel) = .empty;
    errdefer {
        for (out.items) |m| {
            allocator.free(@constCast(m.name));
            allocator.free(@constCast(m.digest));
            allocator.free(@constCast(m.modified_at));
        }
        out.deinit(allocator);
    }

    for (models_val.array.items) |item| {
        if (item != .object) continue;
        const obj = item.object;

        const name_v = obj.get("name") orelse continue;
        if (name_v != .string) continue;

        const size_v = obj.get("size");
        const size: i64 = if (size_v != null and size_v.? == .integer)
            size_v.?.integer
        else
            0;

        const digest_v = obj.get("digest");
        const digest = if (digest_v != null and digest_v.? == .string)
            digest_v.?.string
        else
            "";

        const mod_v = obj.get("modified_at");
        const modified_at = if (mod_v != null and mod_v.? == .string)
            mod_v.?.string
        else
            "";

        try out.append(allocator, .{
            .name = try allocator.dupe(u8, name_v.string),
            .size = size,
            .digest = try allocator.dupe(u8, digest),
            .modified_at = try allocator.dupe(u8, modified_at),
        });
    }

    return out.toOwnedSlice(allocator);
}

pub fn freeOllamaModels(
    allocator: std.mem.Allocator,
    models: []OllamaModel,
) void {
    for (models) |m| {
        allocator.free(@constCast(m.name));
        allocator.free(@constCast(m.digest));
        allocator.free(@constCast(m.modified_at));
    }
    allocator.free(models);
}

test "buildRequestJson creates valid JSON" {
    const allocator = std.testing.allocator;

    const msgs = &[_]Types.Message{
        .{ .role = .system, .content = "You are helpful." },
        .{ .role = .user, .content = "Hello!" },
    };

    const json = try ProviderOllama.buildRequestJson(
        allocator,
        "llama3.2",
        msgs,
        .{ .temperature = 0.7 },
    );
    defer allocator.free(json);

    try std.testing.expect(std.mem.indexOf(u8, json, "\"model\":\"llama3.2\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"stream\":false") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"role\":\"system\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"role\":\"user\"") != null);
}

test "parseResponse extracts content and metadata" {
    const allocator = std.testing.allocator;

    const sample =
        \\{"model":"llama3.2","message":{"role":"assistant","content":"Hello!"},
        \\"prompt_eval_count":26,"eval_count":8,"eval_duration":161064248}
    ;

    const resp = try ProviderOllama.parseResponse(allocator, sample);
    defer allocator.free(resp.content);
    defer if (resp.thinking) |t| allocator.free(t);

    try std.testing.expectEqualStrings("Hello!", resp.content);
    try std.testing.expectEqual(@as(?u32, 26), resp.prompt_tokens);
    try std.testing.expectEqual(@as(?u32, 8), resp.completion_tokens);
    try std.testing.expectEqual(@as(?i64, 161064248), resp.eval_duration_ns);
    try std.testing.expectEqual(@as(?[]const u8, null), resp.thinking);
}

test "parseResponse handles missing metadata" {
    const allocator = std.testing.allocator;

    const sample =
        \\{"model":"llama3.2","message":{"role":"assistant","content":"Hi"}}
    ;

    const resp = try ProviderOllama.parseResponse(allocator, sample);
    defer allocator.free(resp.content);
    defer if (resp.thinking) |t| allocator.free(t);

    try std.testing.expectEqualStrings("Hi", resp.content);
    try std.testing.expectEqual(@as(?u32, null), resp.prompt_tokens);
    try std.testing.expectEqual(@as(?u32, null), resp.completion_tokens);
    try std.testing.expectEqual(@as(?i64, null), resp.eval_duration_ns);
}

test "parseResponse extracts thinking field" {
    const allocator = std.testing.allocator;

    const sample =
        \\{"model":"gpt-oss","message":{"role":"assistant",
        \\"content":"Hello!","thinking":"I should greet the user."}}
    ;

    const resp = try ProviderOllama.parseResponse(allocator, sample);
    defer allocator.free(resp.content);
    defer if (resp.thinking) |t| allocator.free(t);

    try std.testing.expectEqualStrings("Hello!", resp.content);
    try std.testing.expectEqualStrings("I should greet the user.", resp.thinking.?);
}
