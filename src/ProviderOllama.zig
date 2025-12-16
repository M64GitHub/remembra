//! Ollama provider - HTTP client for Ollama's native /api/chat endpoint.
//! Uses stream=false for simplicity.

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

        cli.msg(.dbg, "PAYLOAD:\n{s}", .{payload});

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

test "parseResponse extracts content" {
    const allocator = std.testing.allocator;

    const sample =
        \\{"model":"llama3.2","message":{"role":"assistant","content":"Hello!"}}
    ;

    const content = try ProviderOllama.parseResponse(allocator, sample);
    defer allocator.free(content);

    try std.testing.expectEqualStrings("Hello!", content);
}
