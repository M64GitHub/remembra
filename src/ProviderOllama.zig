//! Ollama provider - HTTP client for Ollama's native /api/chat endpoint.
//! Uses stream=false for simplicity.

const std = @import("std");
const Types = @import("Types.zig");

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
    ) ![]u8 {
        const url = try std.fmt.allocPrint(
            allocator,
            "{s}/api/chat",
            .{trimTrailingSlash(self.base_url)},
        );
        defer allocator.free(url);

        const payload =
            try buildRequestJson(allocator, self.model, msgs, params);
        defer allocator.free(payload);

        const response = try httpPost(allocator, url, payload);
        defer allocator.free(response);

        return parseResponse(allocator, response);
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

    fn parseResponse(allocator: std.mem.Allocator, json: []const u8) ![]u8 {
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

        return allocator.dupe(u8, content.string);
    }
};

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

test "parseResponse extracts content" {
    const allocator = std.testing.allocator;

    const sample =
        \\{"model":"llama3.2","message":{"role":"assistant","content":"Hello!"}}
    ;

    const content = try ProviderOllama.parseResponse(allocator, sample);
    defer allocator.free(content);

    try std.testing.expectEqualStrings("Hello!", content);
}
