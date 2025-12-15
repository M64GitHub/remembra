//! HTTP server for REMEMBRA - Ollama-compatible API layer.

const std = @import("std");
const App = @import("App.zig").App;
const ChatEngine = @import("ChatEngine.zig");
const Cli = @import("Cli.zig").Cli;

const PORT: u16 = 8080;
const READ_BUFFER_SIZE: usize = 16384;
const WRITE_BUFFER_SIZE: usize = 16384;

pub const HttpServer = struct {
    listener: std.net.Server,

    pub fn init() !HttpServer {
        const address = try std.net.Address.parseIp("127.0.0.1", PORT);
        const listener = try address.listen(.{ .reuse_address = true });
        return .{ .listener = listener };
    }

    pub fn deinit(self: *HttpServer) void {
        self.listener.deinit();
    }

    pub fn run(
        self: *HttpServer,
        allocator: std.mem.Allocator,
        app: *App,
    ) !void {
        app.cli.msg(.ok, "Listening on http://127.0.0.1:{d}", .{PORT});

        while (true) {
            const conn = self.listener.accept() catch |err| {
                app.cli.msg(.err, "Accept error: {}", .{err});
                continue;
            };

            handleConnection(allocator, app, conn) catch |err| {
                app.cli.msg(.err, "Connection error: {}", .{err});
            };

            conn.stream.close();
        }
    }
};

fn handleConnection(
    allocator: std.mem.Allocator,
    app: *App,
    conn: std.net.Server.Connection,
) !void {
    var read_buf: [READ_BUFFER_SIZE]u8 = undefined;
    var write_buf: [WRITE_BUFFER_SIZE]u8 = undefined;

    var reader = conn.stream.reader(&read_buf);
    var writer = conn.stream.writer(&write_buf);

    var http_server = std.http.Server.init(
        reader.interface(),
        &writer.interface,
    );

    while (true) {
        var request = http_server.receiveHead() catch |err| {
            if (err == error.EndOfStream) return;
            return err;
        };

        try handleRequest(allocator, app, &request);

        if (!request.head.keep_alive) return;
    }
}

fn handleRequest(
    allocator: std.mem.Allocator,
    app: *App,
    request: *std.http.Server.Request,
) !void {
    const target = request.head.target;
    const method = request.head.method;

    app.cli.msg(.dbg, "{s} {s}", .{ @tagName(method), target });

    if (method == .POST and std.mem.eql(u8, target, "/api/chat")) {
        try handleChat(allocator, app, request);
    } else if (method == .GET and std.mem.eql(u8, target, "/health")) {
        try respondJson(request, "{\"status\":\"ok\"}");
    } else {
        try respondError(request, .not_found, "Not Found");
    }
}

fn handleChat(
    allocator: std.mem.Allocator,
    app: *App,
    request: *std.http.Server.Request,
) !void {
    const content_len = request.head.content_length orelse {
        try respondError(request, .bad_request, "Missing Content-Length");
        return;
    };

    if (content_len > READ_BUFFER_SIZE) {
        try respondError(request, .payload_too_large, "Request too large");
        return;
    }

    var body_buf: [READ_BUFFER_SIZE]u8 = undefined;
    const body_reader = request.readerExpectNone(&body_buf);

    const body = body_reader.readAlloc(allocator, @intCast(content_len)) catch {
        try respondError(request, .bad_request, "Failed to read body");
        return;
    };
    defer allocator.free(body);

    app.cli.msg(.dbg, "Request body: {s}", .{body});

    const user_msg = extractUserMessage(allocator, body) catch |err| {
        app.cli.msg(.wrn, "JSON parse error: {}", .{err});
        try respondError(request, .bad_request, "Invalid JSON");
        return;
    };
    defer allocator.free(user_msg);

    app.cli.msg(.inf, "User: {s}", .{user_msg});

    const reply = ChatEngine.processAndReturn(
        allocator,
        app,
        user_msg,
    ) catch |err| {
        app.cli.msg(.err, "ChatEngine error: {}", .{err});
        try respondError(
            request,
            .internal_server_error,
            "Chat processing failed",
        );
        return;
    };
    defer allocator.free(reply);

    const response = try buildOllamaResponse(allocator, reply);
    defer allocator.free(response);

    try respondJson(request, response);
}

fn extractUserMessage(
    allocator: std.mem.Allocator,
    body: []const u8,
) ![]u8 {
    var parsed = try std.json.parseFromSlice(
        std.json.Value,
        allocator,
        body,
        .{},
    );
    defer parsed.deinit();

    if (parsed.value != .object) return error.InvalidJson;
    const root = parsed.value.object;

    const messages_val =
        root.get("messages") orelse return error.MissingMessages;

    if (messages_val != .array) return error.InvalidMessages;

    const messages = messages_val.array.items;
    if (messages.len == 0) return error.EmptyMessages;

    const last_msg = messages[messages.len - 1];
    if (last_msg != .object) return error.InvalidMessage;

    const content_val = last_msg.object.get("content") orelse
        return error.MissingContent;
    if (content_val != .string) return error.InvalidContent;

    return allocator.dupe(u8, content_val.string);
}

fn buildOllamaResponse(allocator: std.mem.Allocator, reply: []const u8) ![]u8 {
    var escaped: std.ArrayList(u8) = .empty;
    defer escaped.deinit(allocator);

    for (reply) |c| {
        switch (c) {
            '"' => try escaped.appendSlice(allocator, "\\\""),
            '\\' => try escaped.appendSlice(allocator, "\\\\"),
            '\n' => try escaped.appendSlice(allocator, "\\n"),
            '\r' => try escaped.appendSlice(allocator, "\\r"),
            '\t' => try escaped.appendSlice(allocator, "\\t"),
            else => try escaped.append(allocator, c),
        }
    }

    return std.fmt.allocPrint(allocator,
        \\{{"model":"remembra","message":{{"role":"assistant","content":"{s}"}},"done":true}}
    , .{escaped.items});
}

fn respondJson(request: *std.http.Server.Request, body: []const u8) !void {
    try request.respond(body, .{
        .status = .ok,
        .extra_headers = &.{
            .{ .name = "Content-Type", .value = "application/json" },
            .{ .name = "Access-Control-Allow-Origin", .value = "*" },
        },
    });
}

fn respondError(
    request: *std.http.Server.Request,
    status: std.http.Status,
    message: []const u8,
) !void {
    var buf: [256]u8 = undefined;
    const body = std.fmt.bufPrint(
        &buf,
        "{{\"error\":\"{s}\"}}",
        .{message},
    ) catch
        "{\"error\":\"Unknown error\"}";

    try request.respond(body, .{
        .status = status,
        .extra_headers = &.{
            .{ .name = "Content-Type", .value = "application/json" },
            .{ .name = "Access-Control-Allow-Origin", .value = "*" },
        },
    });
}
