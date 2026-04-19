//! OpenRouter provider - HTTPS client for OpenAI-compatible chat
//! completions. Uses std.http.Client.request for TLS streaming.

const std = @import("std");
const Types = @import("Types.zig");
const Cli = @import("Cli.zig").Cli;

pub const ProviderOpenRouter = struct {
    base_url: []u8,
    model: []u8,
    api_key: []u8,

    pub fn init(
        allocator: std.mem.Allocator,
        base_url: []const u8,
        model: []const u8,
        api_key: []const u8,
    ) !ProviderOpenRouter {
        return .{
            .base_url = try allocator.dupe(u8, base_url),
            .model = try allocator.dupe(u8, model),
            .api_key = try allocator.dupe(u8, api_key),
        };
    }

    pub fn deinit(
        self: *ProviderOpenRouter,
        allocator: std.mem.Allocator,
    ) void {
        allocator.free(self.base_url);
        allocator.free(self.model);
        allocator.free(self.api_key);
    }

    pub fn chat(
        self: *ProviderOpenRouter,
        allocator: std.mem.Allocator,
        msgs: []const Types.Message,
        params: Types.ChatParams,
        cli: *Cli,
    ) !Types.ChatResponse {
        const url = try buildEndpoint(allocator, self.base_url);
        defer allocator.free(url);

        const payload = try buildRequestJson(
            allocator,
            self.model,
            msgs,
            params,
            false,
        );
        defer allocator.free(payload);

        cli.msg(.dbg, "OR PAYLOAD:\n{s}", .{payload});

        const t_start = std.time.nanoTimestamp();
        const body = try httpPost(
            allocator,
            url,
            payload,
            self.api_key,
            cli,
        );
        defer allocator.free(body);
        const t_end = std.time.nanoTimestamp();
        const wall_ns: i64 = @intCast(t_end - t_start);

        cli.msg(.dbg, "OR RESPONSE:\n{s}", .{body});

        return parseResponse(allocator, body, wall_ns);
    }

    pub fn chatStream(
        self: *ProviderOpenRouter,
        allocator: std.mem.Allocator,
        msgs: []const Types.Message,
        params: Types.ChatParams,
        cli: *Cli,
        writer: anytype,
    ) !Types.StreamResult {
        const url = try buildEndpoint(allocator, self.base_url);
        defer allocator.free(url);

        const payload = try buildRequestJson(
            allocator,
            self.model,
            msgs,
            params,
            true,
        );
        defer allocator.free(payload);

        cli.msg(.dbg, "OR STREAM PAYLOAD:\n{s}", .{payload});

        return httpPostStream(
            allocator,
            url,
            payload,
            self.api_key,
            cli,
            writer,
        );
    }

    fn httpPostStream(
        allocator: std.mem.Allocator,
        url: []const u8,
        payload: []const u8,
        api_key: []const u8,
        cli: *Cli,
        output_writer: anytype,
    ) !Types.StreamResult {
        var client: std.http.Client = .{ .allocator = allocator };
        defer client.deinit();

        const uri = std.Uri.parse(url) catch return error.InvalidUrl;

        const auth = try std.fmt.allocPrint(
            allocator,
            "Bearer {s}",
            .{api_key},
        );
        defer allocator.free(auth);

        const payload_mut = try allocator.dupe(u8, payload);
        defer allocator.free(payload_mut);

        var req = try client.request(.POST, uri, .{
            .headers = .{
                .authorization = .{ .override = auth },
                .content_type = .{ .override = "application/json" },
            },
            .extra_headers = &.{
                .{
                    .name = "HTTP-Referer",
                    .value = "http://127.0.0.1",
                },
                .{ .name = "X-Title", .value = "REMEMBRA" },
            },
            .keep_alive = false,
        });
        defer req.deinit();

        req.transfer_encoding = .{ .content_length = payload_mut.len };
        try req.sendBodyComplete(payload_mut);

        var redirect_buf: [1024]u8 = undefined;
        var response = try req.receiveHead(&redirect_buf);

        const status = response.head.status;
        if (@intFromEnum(status) >= 400) {
            cli.msg(.err, "OpenRouter HTTP {d} ({s})", .{
                @intFromEnum(status),
                @tagName(status),
            });
            return mapHttpError(status);
        }

        const t_start = std.time.nanoTimestamp();
        var transfer_buf: [8192]u8 = undefined;
        const reader = response.reader(&transfer_buf);

        var stats: Types.StreamStats = .{};
        var content_buf: std.ArrayListUnmanaged(u8) = .empty;
        errdefer content_buf.deinit(allocator);

        var line_buf: [32768]u8 = undefined;
        var finished = false;

        while (!finished) {
            const n = readLine(reader, &line_buf) catch |err| {
                if (err == error.EndOfStream) break;
                return err;
            };

            if (n == 0) continue;
            const line = line_buf[0..n];
            if (line[0] == ':') continue;
            if (!std.mem.startsWith(u8, line, "data: ")) continue;

            const body = line["data: ".len..];

            if (std.mem.eql(u8, body, "[DONE]")) {
                finished = true;
                break;
            }

            const chunk = parseStreamChunk(allocator, body) catch |err| {
                cli.msg(.wrn, "OR parse chunk failed: {}", .{err});
                continue;
            };
            defer allocator.free(chunk.content);
            defer allocator.free(chunk.thinking);

            if (chunk.content.len > 0) {
                try content_buf.appendSlice(
                    allocator,
                    chunk.content,
                );
            }

            if (chunk.prompt_tokens) |pt| stats.prompt_tokens = pt;
            if (chunk.completion_tokens) |ct|
                stats.completion_tokens = ct;

            const has_text = chunk.content.len > 0 or
                chunk.thinking.len > 0;
            if (has_text and !chunk.done) {
                writeSseEvent(output_writer, chunk) catch |err| {
                    cli.msg(.wrn, "OR write SSE failed: {}", .{err});
                    return error.WriteError;
                };
                output_writer.flush() catch {};
            }

            if (chunk.done) {
                finished = true;
                break;
            }
        }

        const t_end = std.time.nanoTimestamp();
        stats.eval_duration_ns = @intCast(t_end - t_start);

        const done_chunk = Types.StreamChunk{
            .content = "",
            .thinking = "",
            .done = true,
            .prompt_tokens = stats.prompt_tokens,
            .completion_tokens = stats.completion_tokens,
            .eval_duration_ns = stats.eval_duration_ns,
        };
        writeSseEvent(output_writer, done_chunk) catch {};
        output_writer.flush() catch {};

        return .{
            .stats = stats,
            .content = try content_buf.toOwnedSlice(allocator),
        };
    }

    fn httpPost(
        allocator: std.mem.Allocator,
        url: []const u8,
        payload: []const u8,
        api_key: []const u8,
        cli: *Cli,
    ) ![]u8 {
        var client: std.http.Client = .{ .allocator = allocator };
        defer client.deinit();

        const auth = try std.fmt.allocPrint(
            allocator,
            "Bearer {s}",
            .{api_key},
        );
        defer allocator.free(auth);

        var response_writer: std.Io.Writer.Allocating =
            .init(allocator);
        errdefer response_writer.deinit();

        const result = try client.fetch(.{
            .location = .{ .url = url },
            .method = .POST,
            .payload = payload,
            .headers = .{
                .authorization = .{ .override = auth },
                .content_type = .{ .override = "application/json" },
            },
            .extra_headers = &.{
                .{
                    .name = "HTTP-Referer",
                    .value = "http://127.0.0.1",
                },
                .{ .name = "X-Title", .value = "REMEMBRA" },
            },
            .response_writer = &response_writer.writer,
        });

        if (@intFromEnum(result.status) >= 400) {
            cli.msg(.err, "OpenRouter HTTP {d} ({s})", .{
                @intFromEnum(result.status),
                @tagName(result.status),
            });
            return mapHttpError(result.status);
        }

        var list = response_writer.toArrayList();
        defer list.deinit(allocator);
        return allocator.dupe(u8, list.items);
    }

    fn mapHttpError(status: std.http.Status) anyerror {
        return switch (@intFromEnum(status)) {
            401 => error.OpenRouterAuthFailed,
            402 => error.OpenRouterOutOfCredit,
            429 => error.OpenRouterRateLimit,
            else => error.OpenRouterHttpError,
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
                if (pos > 0 and buf[pos - 1] == '\r') return pos - 1;
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
        ) catch return error.OpenRouterInvalidJson;
        defer parsed.deinit();

        const root = parsed.value;
        if (root != .object) return error.OpenRouterInvalidJson;

        var content_str: []const u8 = "";
        var thinking_str: []const u8 = "";
        var is_done = false;

        if (root.object.get("choices")) |choices_v| {
            if (choices_v == .array and choices_v.array.items.len > 0) {
                const first = choices_v.array.items[0];
                if (first == .object) {
                    if (first.object.get("delta")) |delta| {
                        if (delta == .object) {
                            if (delta.object.get("content")) |c| {
                                if (c == .string)
                                    content_str = c.string;
                            }
                            const tv =
                                delta.object.get("reasoning") orelse
                                delta.object.get("reasoning_content");
                            if (tv) |t| {
                                if (t == .string)
                                    thinking_str = t.string;
                            }
                        }
                    }
                    if (first.object.get("finish_reason")) |fr| {
                        if (fr == .string) is_done = true;
                    }
                }
            }
        }

        var prompt_tokens: ?u32 = null;
        var completion_tokens: ?u32 = null;
        if (root.object.get("usage")) |usage| {
            if (usage == .object) {
                prompt_tokens = extractOptionalInt(
                    usage.object,
                    "prompt_tokens",
                );
                completion_tokens = extractOptionalInt(
                    usage.object,
                    "completion_tokens",
                );
            }
        }

        const content = try allocator.dupe(u8, content_str);
        errdefer allocator.free(content);
        const thinking = try allocator.dupe(u8, thinking_str);

        return .{
            .content = content,
            .thinking = thinking,
            .done = is_done,
            .prompt_tokens = prompt_tokens,
            .completion_tokens = completion_tokens,
            .eval_duration_ns = null,
        };
    }

    fn writeSseEvent(
        writer: anytype,
        chunk: Types.StreamChunk,
    ) !void {
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
        for (s) |ch| {
            switch (ch) {
                '\\' => try writer.writeAll("\\\\"),
                '"' => try writer.writeAll("\\\""),
                '\n' => try writer.writeAll("\\n"),
                '\r' => try writer.writeAll("\\r"),
                '\t' => try writer.writeAll("\\t"),
                else => try writer.writeByte(ch),
            }
        }
    }

    fn buildEndpoint(
        allocator: std.mem.Allocator,
        base_url: []const u8,
    ) ![]u8 {
        return std.fmt.allocPrint(
            allocator,
            "{s}/chat/completions",
            .{trimTrailingSlash(base_url)},
        );
    }

    fn trimTrailingSlash(s: []const u8) []const u8 {
        if (s.len == 0) return s;
        if (s[s.len - 1] == '/') return s[0 .. s.len - 1];
        return s;
    }

    fn buildRequestJson(
        allocator: std.mem.Allocator,
        model: []const u8,
        msgs: []const Types.Message,
        params: Types.ChatParams,
        stream: bool,
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

        try out.appendSlice(allocator, "]");
        if (stream) {
            try out.appendSlice(allocator, ",\"stream\":true");
        }

        try out.writer(allocator).print(
            ",\"temperature\":{d:.2}",
            .{params.temperature},
        );
        try out.writer(allocator).print(
            ",\"max_tokens\":{d}",
            .{params.max_tokens},
        );

        try out.append(allocator, '}');
        return out.toOwnedSlice(allocator);
    }

    fn appendJsonEscaped(
        out: *std.ArrayListUnmanaged(u8),
        allocator: std.mem.Allocator,
        s: []const u8,
    ) !void {
        for (s) |ch| {
            switch (ch) {
                '\\' => try out.appendSlice(allocator, "\\\\"),
                '"' => try out.appendSlice(allocator, "\\\""),
                '\n' => try out.appendSlice(allocator, "\\n"),
                '\r' => try out.appendSlice(allocator, "\\r"),
                '\t' => try out.appendSlice(allocator, "\\t"),
                else => try out.append(allocator, ch),
            }
        }
    }

    fn parseResponse(
        allocator: std.mem.Allocator,
        json: []const u8,
        wall_ns: i64,
    ) !Types.ChatResponse {
        var parsed = std.json.parseFromSlice(
            std.json.Value,
            allocator,
            json,
            .{},
        ) catch return error.OpenRouterInvalidJson;
        defer parsed.deinit();

        const root = parsed.value;
        if (root != .object) return error.OpenRouterInvalidJson;

        const choices_v =
            root.object.get("choices") orelse
            return error.OpenRouterInvalidJson;
        if (choices_v != .array or choices_v.array.items.len == 0)
            return error.OpenRouterInvalidJson;

        const first = choices_v.array.items[0];
        if (first != .object) return error.OpenRouterInvalidJson;

        const msg_v =
            first.object.get("message") orelse
            return error.OpenRouterInvalidJson;
        if (msg_v != .object) return error.OpenRouterInvalidJson;

        const content_v =
            msg_v.object.get("content") orelse
            return error.OpenRouterInvalidJson;
        if (content_v != .string) return error.OpenRouterInvalidJson;

        const thinking = try extractOptionalString(
            allocator,
            msg_v.object,
            "reasoning",
        );

        var prompt_tokens: ?u32 = null;
        var completion_tokens: ?u32 = null;
        if (root.object.get("usage")) |usage| {
            if (usage == .object) {
                prompt_tokens = extractOptionalInt(
                    usage.object,
                    "prompt_tokens",
                );
                completion_tokens = extractOptionalInt(
                    usage.object,
                    "completion_tokens",
                );
            }
        }

        return .{
            .content = try allocator.dupe(u8, content_v.string),
            .thinking = thinking,
            .prompt_tokens = prompt_tokens,
            .completion_tokens = completion_tokens,
            .eval_duration_ns = wall_ns,
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

    fn extractOptionalString(
        allocator: std.mem.Allocator,
        obj: std.json.ObjectMap,
        key: []const u8,
    ) !?[]const u8 {
        const val = obj.get(key) orelse return null;
        if (val != .string) return null;
        if (val.string.len == 0) return null;
        return try allocator.dupe(u8, val.string);
    }
};

pub const OpenRouterModel = struct {
    id: []const u8,
    name: []const u8,
    context_length: i64,
};

pub fn discoverModels(
    allocator: std.mem.Allocator,
    base_url: []const u8,
    api_key: []const u8,
) ![]OpenRouterModel {
    const url = try std.fmt.allocPrint(
        allocator,
        "{s}/models",
        .{trimUrl(base_url)},
    );
    defer allocator.free(url);

    const response = httpGet(allocator, url, api_key) catch {
        return allocator.alloc(OpenRouterModel, 0);
    };
    defer allocator.free(response);

    return parseModelsResponse(allocator, response);
}

fn httpGet(
    allocator: std.mem.Allocator,
    url: []const u8,
    api_key: []const u8,
) ![]u8 {
    var client: std.http.Client = .{ .allocator = allocator };
    defer client.deinit();

    var response_writer: std.Io.Writer.Allocating = .init(allocator);
    errdefer response_writer.deinit();

    const auth = if (api_key.len > 0)
        try std.fmt.allocPrint(
            allocator,
            "Bearer {s}",
            .{api_key},
        )
    else
        try allocator.dupe(u8, "");
    defer allocator.free(auth);

    const auth_value: std.http.Client.Request.Headers.Value =
        if (api_key.len > 0) .{ .override = auth } else .default;

    const result = client.fetch(.{
        .location = .{ .url = url },
        .method = .GET,
        .headers = .{ .authorization = auth_value },
        .response_writer = &response_writer.writer,
    }) catch return error.OpenRouterHttpError;

    if (result.status != .ok) {
        return error.OpenRouterHttpError;
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

fn parseModelsResponse(
    allocator: std.mem.Allocator,
    json: []const u8,
) ![]OpenRouterModel {
    var parsed = std.json.parseFromSlice(
        std.json.Value,
        allocator,
        json,
        .{},
    ) catch return allocator.alloc(OpenRouterModel, 0);
    defer parsed.deinit();

    const root = parsed.value;
    if (root != .object) return allocator.alloc(OpenRouterModel, 0);

    const data_v = root.object.get("data") orelse
        return allocator.alloc(OpenRouterModel, 0);
    if (data_v != .array)
        return allocator.alloc(OpenRouterModel, 0);

    var out: std.ArrayList(OpenRouterModel) = .empty;
    errdefer {
        for (out.items) |m| {
            allocator.free(@constCast(m.id));
            allocator.free(@constCast(m.name));
        }
        out.deinit(allocator);
    }

    for (data_v.array.items) |item| {
        if (item != .object) continue;
        const obj = item.object;

        const id_v = obj.get("id") orelse continue;
        if (id_v != .string) continue;

        const name_v = obj.get("name");
        const name = if (name_v != null and name_v.? == .string)
            name_v.?.string
        else
            id_v.string;

        const ctx_v = obj.get("context_length");
        const ctx: i64 = if (ctx_v != null and ctx_v.? == .integer)
            ctx_v.?.integer
        else
            0;

        try out.append(allocator, .{
            .id = try allocator.dupe(u8, id_v.string),
            .name = try allocator.dupe(u8, name),
            .context_length = ctx,
        });
    }

    return out.toOwnedSlice(allocator);
}

pub fn freeOpenRouterModels(
    allocator: std.mem.Allocator,
    models: []OpenRouterModel,
) void {
    for (models) |m| {
        allocator.free(@constCast(m.id));
        allocator.free(@constCast(m.name));
    }
    allocator.free(models);
}

test "buildRequestJson non-streaming includes model and messages" {
    const allocator = std.testing.allocator;

    const msgs = &[_]Types.Message{
        .{ .role = .system, .content = "You are helpful." },
        .{ .role = .user, .content = "Hi!" },
    };

    const json = try ProviderOpenRouter.buildRequestJson(
        allocator,
        "openai/gpt-4o-mini",
        msgs,
        .{ .temperature = 0.7, .max_tokens = 256 },
        false,
    );
    defer allocator.free(json);

    try std.testing.expect(std.mem.indexOf(
        u8,
        json,
        "\"model\":\"openai/gpt-4o-mini\"",
    ) != null);
    try std.testing.expect(std.mem.indexOf(
        u8,
        json,
        "\"stream\":true",
    ) == null);
    try std.testing.expect(std.mem.indexOf(
        u8,
        json,
        "\"max_tokens\":256",
    ) != null);
}

test "buildRequestJson streaming sets stream:true" {
    const allocator = std.testing.allocator;

    const msgs = &[_]Types.Message{
        .{ .role = .user, .content = "hi" },
    };

    const json = try ProviderOpenRouter.buildRequestJson(
        allocator,
        "anthropic/claude-3.5-haiku",
        msgs,
        .{ .temperature = 0.2, .max_tokens = 50 },
        true,
    );
    defer allocator.free(json);

    try std.testing.expect(std.mem.indexOf(
        u8,
        json,
        "\"stream\":true",
    ) != null);
}

test "parseStreamChunk extracts content delta" {
    const allocator = std.testing.allocator;

    const sample =
        \\{"choices":[{"index":0,"delta":{"content":"Hello","role":"assistant"}}]}
    ;

    const chunk = try ProviderOpenRouter.parseStreamChunk(
        allocator,
        sample,
    );
    defer allocator.free(chunk.content);
    defer allocator.free(chunk.thinking);

    try std.testing.expectEqualStrings("Hello", chunk.content);
    try std.testing.expectEqualStrings("", chunk.thinking);
    try std.testing.expectEqual(false, chunk.done);
}

test "parseStreamChunk extracts reasoning delta" {
    const allocator = std.testing.allocator;

    const sample =
        \\{"choices":[{"index":0,"delta":{"reasoning":"thinking..."}}]}
    ;

    const chunk = try ProviderOpenRouter.parseStreamChunk(
        allocator,
        sample,
    );
    defer allocator.free(chunk.content);
    defer allocator.free(chunk.thinking);

    try std.testing.expectEqualStrings("", chunk.content);
    try std.testing.expectEqualStrings("thinking...", chunk.thinking);
}

test "parseStreamChunk detects finish_reason as done" {
    const allocator = std.testing.allocator;

    const sample =
        \\{"choices":[{"index":0,"delta":{"content":""},"finish_reason":"stop"}]}
    ;

    const chunk = try ProviderOpenRouter.parseStreamChunk(
        allocator,
        sample,
    );
    defer allocator.free(chunk.content);
    defer allocator.free(chunk.thinking);

    try std.testing.expectEqual(true, chunk.done);
}

test "parseStreamChunk extracts usage from final chunk" {
    const allocator = std.testing.allocator;

    const sample =
        \\{"choices":[{"delta":{},"finish_reason":"stop"}],
        \\"usage":{"prompt_tokens":22,"completion_tokens":79}}
    ;

    const chunk = try ProviderOpenRouter.parseStreamChunk(
        allocator,
        sample,
    );
    defer allocator.free(chunk.content);
    defer allocator.free(chunk.thinking);

    try std.testing.expectEqual(@as(?u32, 22), chunk.prompt_tokens);
    try std.testing.expectEqual(@as(?u32, 79), chunk.completion_tokens);
}

test "parseResponse reads content and usage" {
    const allocator = std.testing.allocator;

    const sample =
        \\{"id":"abc","choices":[{"message":{"role":"assistant",
        \\"content":"Hi there!"}}],
        \\"usage":{"prompt_tokens":9,"completion_tokens":3}}
    ;

    const resp = try ProviderOpenRouter.parseResponse(
        allocator,
        sample,
        100_000_000,
    );
    defer allocator.free(resp.content);
    defer if (resp.thinking) |t| allocator.free(t);

    try std.testing.expectEqualStrings("Hi there!", resp.content);
    try std.testing.expectEqual(@as(?u32, 9), resp.prompt_tokens);
    try std.testing.expectEqual(@as(?u32, 3), resp.completion_tokens);
    try std.testing.expectEqual(
        @as(?i64, 100_000_000),
        resp.eval_duration_ns,
    );
}

test "parseResponse extracts reasoning field" {
    const allocator = std.testing.allocator;

    const sample =
        \\{"choices":[{"message":{"role":"assistant",
        \\"content":"Answer","reasoning":"Let me think..."}}]}
    ;

    const resp = try ProviderOpenRouter.parseResponse(
        allocator,
        sample,
        0,
    );
    defer allocator.free(resp.content);
    defer if (resp.thinking) |t| allocator.free(t);

    try std.testing.expectEqualStrings("Answer", resp.content);
    try std.testing.expectEqualStrings(
        "Let me think...",
        resp.thinking.?,
    );
}
