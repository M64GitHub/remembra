//! HTTP server for REMEMBRA - Ollama-compatible API layer.

const std = @import("std");
const App = @import("App.zig").App;
const ChatEngine = @import("ChatEngine.zig");
const Cli = @import("Cli.zig").Cli;
const Types = @import("Types.zig");
const MemoryStore = @import("MemoryStoreSqlite.zig");
const EventKind = MemoryStore.EventKind;

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
    } else if (method == .GET and startsWith(target, "/api/memories")) {
        try handleGetMemories(allocator, app, request);
    } else if (method == .POST and std.mem.eql(u8, target, "/api/memories")) {
        try handlePostMemory(allocator, app, request);
    } else if (method == .DELETE and startsWith(target, "/api/memories/")) {
        try handleDeleteMemory(allocator, app, request);
    } else if (method == .GET and startsWith(target, "/api/events")) {
        try handleGetEvents(allocator, app, request);
    } else if (method == .GET and std.mem.eql(u8, target, "/api/thoughts")) {
        try handleGetThoughts(allocator, app, request);
    } else if (method == .GET and std.mem.eql(u8, target, "/api/episodes")) {
        try handleGetEpisodes(allocator, app, request);
    } else if (method == .GET and
        std.mem.eql(u8, target, "/api/profiles/providers"))
    {
        try handleGetProviders(allocator, app, request);
    } else if (method == .POST and
        std.mem.eql(u8, target, "/api/profiles/providers"))
    {
        try handlePostProvider(allocator, app, request);
    } else if (method == .DELETE and
        startsWith(target, "/api/profiles/providers/"))
    {
        try handleDeleteProvider(allocator, app, request);
    } else if (method == .GET and
        std.mem.eql(u8, target, "/api/profiles/personas"))
    {
        try handleGetPersonas(allocator, app, request);
    } else if (method == .POST and
        std.mem.eql(u8, target, "/api/profiles/personas"))
    {
        try handlePostPersona(allocator, app, request);
    } else if (method == .DELETE and
        startsWith(target, "/api/profiles/personas/"))
    {
        try handleDeletePersona(allocator, app, request);
    } else if (method == .GET and
        std.mem.eql(u8, target, "/api/profiles/active"))
    {
        try handleGetActiveProfiles(app, request);
    } else if (method == .POST and
        std.mem.eql(u8, target, "/api/profiles/active"))
    {
        try handlePostActiveProfiles(allocator, app, request);
    } else if (method == .GET) {
        try handleStaticFile(allocator, request);
    } else {
        try respondError(request, .not_found, "Not Found");
    }
}

fn startsWith(haystack: []const u8, needle: []const u8) bool {
    return haystack.len >= needle.len and
        std.mem.eql(u8, haystack[0..needle.len], needle);
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

fn handleGetMemories(
    allocator: std.mem.Allocator,
    app: *App,
    request: *std.http.Server.Request,
) !void {
    const target = request.head.target;
    const show_all = std.mem.indexOf(u8, target, "all=true") != null;

    const memories = if (show_all)
        try app.store.loadAllMemoryItems(allocator)
    else
        try app.store.loadMemoryItems(allocator, 100);

    defer {
        for (memories) |m| {
            allocator.free(@constCast(m.subject));
            allocator.free(@constCast(m.predicate));
            allocator.free(@constCast(m.object));
        }
        allocator.free(memories);
    }

    const json = try buildMemoriesJson(allocator, memories);
    defer allocator.free(json);

    try respondJson(request, json);
}

fn handlePostMemory(
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

    const mem_input = parseMemoryInput(allocator, body) catch {
        try respondError(request, .bad_request, "Invalid JSON");
        return;
    };
    defer {
        allocator.free(mem_input.subject);
        allocator.free(mem_input.predicate);
        allocator.free(mem_input.object);
    }

    const id = app.store.addMemory(allocator, .{
        .kind = mem_input.kind,
        .subject = mem_input.subject,
        .predicate = mem_input.predicate,
        .object = mem_input.object,
        .confidence = mem_input.confidence,
        .is_active = true,
    }) catch {
        try respondError(request, .internal_server_error, "Failed to store");
        return;
    };

    var buf: [64]u8 = undefined;
    const resp = std.fmt.bufPrint(&buf, "{{\"id\":{d}}}", .{id}) catch
        "{\"id\":0}";

    try respondJson(request, resp);
}

fn handleDeleteMemory(
    allocator: std.mem.Allocator,
    app: *App,
    request: *std.http.Server.Request,
) !void {
    _ = allocator;
    const target = request.head.target;

    const prefix = "/api/memories/";
    if (target.len <= prefix.len) {
        try respondError(request, .bad_request, "Missing memory ID");
        return;
    }

    const id_str = target[prefix.len..];
    const id = std.fmt.parseInt(i64, id_str, 10) catch {
        try respondError(request, .bad_request, "Invalid memory ID");
        return;
    };

    app.store.deactivateMemory(id) catch {
        try respondError(request, .internal_server_error, "Deactivate failed");
        return;
    };

    try respondJson(request, "{\"success\":true}");
}

fn handleGetEvents(
    allocator: std.mem.Allocator,
    app: *App,
    request: *std.http.Server.Request,
) !void {
    const target = request.head.target;

    var since_ms: ?i64 = null;
    var kind_filter: ?EventKind = null;
    var limit: usize = 50;

    if (std.mem.indexOf(u8, target, "?")) |q_idx| {
        const query = target[q_idx + 1 ..];
        since_ms = parseQueryInt(query, "since");
        limit = @intCast(parseQueryInt(query, "limit") orelse 50);

        if (parseQueryStr(query, "kind")) |kind_str| {
            kind_filter = parseEventKind(kind_str);
        }
    }

    const events = try app.store.queryEvents(
        allocator,
        since_ms,
        kind_filter,
        limit,
    );
    defer {
        for (events) |e| {
            allocator.free(@constCast(e.subject));
            allocator.free(@constCast(e.details));
            if (e.session_id) |sid| allocator.free(@constCast(sid));
        }
        allocator.free(events);
    }

    const json = try buildEventsJson(allocator, events);
    defer allocator.free(json);

    try respondJson(request, json);
}

fn handleGetThoughts(
    allocator: std.mem.Allocator,
    app: *App,
    request: *std.http.Server.Request,
) !void {
    const memories = try app.store.loadAllMemoryItems(allocator);
    defer {
        for (memories) |m| {
            allocator.free(@constCast(m.subject));
            allocator.free(@constCast(m.predicate));
            allocator.free(@constCast(m.object));
        }
        allocator.free(memories);
    }

    var thoughts: std.ArrayList(Types.MemoryItem) = .empty;
    defer thoughts.deinit(allocator);

    for (memories) |m| {
        if (std.mem.eql(u8, m.subject, "self") and
            std.mem.eql(u8, m.predicate, "thought"))
        {
            try thoughts.append(allocator, m);
        }
    }

    const json = try buildMemoriesJson(allocator, thoughts.items);
    defer allocator.free(json);

    try respondJson(request, json);
}

fn handleGetEpisodes(
    allocator: std.mem.Allocator,
    app: *App,
    request: *std.http.Server.Request,
) !void {
    const memories = try app.store.loadAllMemoryItems(allocator);
    defer {
        for (memories) |m| {
            allocator.free(@constCast(m.subject));
            allocator.free(@constCast(m.predicate));
            allocator.free(@constCast(m.object));
        }
        allocator.free(memories);
    }

    var episodes: std.ArrayList(Types.MemoryItem) = .empty;
    defer episodes.deinit(allocator);

    for (memories) |m| {
        if (std.mem.eql(u8, m.subject, "episode") and
            std.mem.eql(u8, m.predicate, "summary"))
        {
            try episodes.append(allocator, m);
        }
    }

    const json = try buildMemoriesJson(allocator, episodes.items);
    defer allocator.free(json);

    try respondJson(request, json);
}

const MemoryInput = struct {
    kind: Types.MemoryKind,
    subject: []u8,
    predicate: []u8,
    object: []u8,
    confidence: f32,
};

fn parseMemoryInput(
    allocator: std.mem.Allocator,
    body: []const u8,
) !MemoryInput {
    var parsed = try std.json.parseFromSlice(
        std.json.Value,
        allocator,
        body,
        .{},
    );
    defer parsed.deinit();

    if (parsed.value != .object) return error.InvalidJson;
    const root = parsed.value.object;

    const subject_v = root.get("subject") orelse return error.MissingSubject;
    const predicate_v =
        root.get("predicate") orelse return error.MissingPredicate;
    const object_v = root.get("object") orelse return error.MissingObject;

    if (subject_v != .string) return error.InvalidSubject;
    if (predicate_v != .string) return error.InvalidPredicate;
    if (object_v != .string) return error.InvalidObject;

    var kind: Types.MemoryKind = .note;
    if (root.get("kind")) |kind_v| {
        if (kind_v == .string) {
            if (std.mem.eql(u8, kind_v.string, "fact")) kind = .fact;
            if (std.mem.eql(u8, kind_v.string, "preference")) kind = .preference;
            if (std.mem.eql(u8, kind_v.string, "project")) kind = .project;
        }
    }

    var confidence: f32 = 0.8;
    if (root.get("confidence")) |conf_v| {
        confidence = switch (conf_v) {
            .float => @floatCast(conf_v.float),
            .integer => @floatFromInt(conf_v.integer),
            else => 0.8,
        };
    }

    return .{
        .kind = kind,
        .subject = try allocator.dupe(u8, subject_v.string),
        .predicate = try allocator.dupe(u8, predicate_v.string),
        .object = try allocator.dupe(u8, object_v.string),
        .confidence = confidence,
    };
}

fn buildMemoriesJson(
    allocator: std.mem.Allocator,
    memories: []const Types.MemoryItem,
) ![]u8 {
    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(allocator);

    try out.appendSlice(allocator, "{\"memories\":[");

    for (memories, 0..) |m, i| {
        if (i > 0) try out.append(allocator, ',');

        const escaped_obj = try escapeJsonString(allocator, m.object);
        defer allocator.free(escaped_obj);

        try out.writer(allocator).print(
            "{{\"id\":{d},\"kind\":\"{s}\",\"subject\":\"{s}\"," ++
                "\"predicate\":\"{s}\",\"object\":\"{s}\"," ++
                "\"confidence\":{d:.2},\"is_active\":{s}," ++
                "\"created_at_ms\":{d},\"updated_at_ms\":{d}}}",
            .{
                m.id,
                @tagName(m.kind),
                m.subject,
                m.predicate,
                escaped_obj,
                m.confidence,
                if (m.is_active) "true" else "false",
                m.created_at_ms,
                m.updated_at_ms,
            },
        );
    }

    try out.appendSlice(allocator, "]}");
    return out.toOwnedSlice(allocator);
}

fn buildEventsJson(
    allocator: std.mem.Allocator,
    events: []const MemoryStore.Event,
) ![]u8 {
    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(allocator);

    try out.appendSlice(allocator, "{\"events\":[");

    for (events, 0..) |e, i| {
        if (i > 0) try out.append(allocator, ',');

        const escaped_details = try escapeJsonString(allocator, e.details);
        defer allocator.free(escaped_details);

        try out.writer(allocator).print(
            "{{\"id\":{d},\"kind\":\"{s}\",\"timestamp_ms\":{d}," ++
                "\"subject\":\"{s}\",\"details\":\"{s}\"}}",
            .{
                e.id,
                @tagName(e.kind),
                e.timestamp_ms,
                e.subject,
                escaped_details,
            },
        );
    }

    try out.appendSlice(allocator, "]}");
    return out.toOwnedSlice(allocator);
}

fn escapeJsonString(allocator: std.mem.Allocator, s: []const u8) ![]u8 {
    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(allocator);

    for (s) |ch| {
        switch (ch) {
            '"' => try out.appendSlice(allocator, "\\\""),
            '\\' => try out.appendSlice(allocator, "\\\\"),
            '\n' => try out.appendSlice(allocator, "\\n"),
            '\r' => try out.appendSlice(allocator, "\\r"),
            '\t' => try out.appendSlice(allocator, "\\t"),
            else => try out.append(allocator, ch),
        }
    }

    return out.toOwnedSlice(allocator);
}

fn parseQueryInt(query: []const u8, key: []const u8) ?i64 {
    var iter = std.mem.splitScalar(u8, query, '&');
    while (iter.next()) |pair| {
        if (std.mem.indexOf(u8, pair, "=")) |eq_idx| {
            const k = pair[0..eq_idx];
            const v = pair[eq_idx + 1 ..];
            if (std.mem.eql(u8, k, key)) {
                return std.fmt.parseInt(i64, v, 10) catch null;
            }
        }
    }
    return null;
}

fn parseQueryStr(query: []const u8, key: []const u8) ?[]const u8 {
    var iter = std.mem.splitScalar(u8, query, '&');
    while (iter.next()) |pair| {
        if (std.mem.indexOf(u8, pair, "=")) |eq_idx| {
            const k = pair[0..eq_idx];
            const v = pair[eq_idx + 1 ..];
            if (std.mem.eql(u8, k, key)) {
                return v;
            }
        }
    }
    return null;
}

fn parseEventKind(s: []const u8) ?EventKind {
    if (std.mem.eql(u8, s, "memory_proposed")) return .memory_proposed;
    if (std.mem.eql(u8, s, "memory_stored")) return .memory_stored;
    if (std.mem.eql(u8, s, "memory_decayed")) return .memory_decayed;
    if (std.mem.eql(u8, s, "memory_rejected")) return .memory_rejected;
    if (std.mem.eql(u8, s, "episode_compacted")) return .episode_compacted;
    if (std.mem.eql(u8, s, "thought_generated")) return .thought_generated;
    if (std.mem.eql(u8, s, "governor_blocked")) return .governor_blocked;
    if (std.mem.eql(u8, s, "governor_accepted")) return .governor_accepted;
    if (std.mem.eql(u8, s, "context_built")) return .context_built;
    if (std.mem.eql(u8, s, "chat_completed")) return .chat_completed;
    if (std.mem.eql(u8, s, "security_warning")) return .security_warning;
    return null;
}

fn handleGetProviders(
    allocator: std.mem.Allocator,
    app: *App,
    request: *std.http.Server.Request,
) !void {
    const providers = try app.store.listProviderProfiles(allocator);
    defer {
        for (providers) |p| MemoryStore.freeProviderProfile(allocator, p);
        allocator.free(providers);
    }

    const json = try buildProvidersJson(allocator, providers);
    defer allocator.free(json);

    try respondJson(request, json);
}

fn handlePostProvider(
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

    const input = parseProviderInput(allocator, body) catch {
        try respondError(request, .bad_request, "Invalid JSON");
        return;
    };
    defer {
        allocator.free(input.name);
        allocator.free(input.ollama_url);
        allocator.free(input.model);
    }

    const id = app.store.createProviderProfile(
        input.name,
        input.ollama_url,
        input.model,
    ) catch {
        try respondError(request, .internal_server_error, "Failed to create");
        return;
    };

    var buf: [64]u8 = undefined;
    const resp = std.fmt.bufPrint(&buf, "{{\"id\":{d}}}", .{id}) catch
        "{\"id\":0}";

    try respondJson(request, resp);
}

fn handleDeleteProvider(
    allocator: std.mem.Allocator,
    app: *App,
    request: *std.http.Server.Request,
) !void {
    _ = allocator;
    const target = request.head.target;
    const prefix = "/api/profiles/providers/";

    if (target.len <= prefix.len) {
        try respondError(request, .bad_request, "Missing provider ID");
        return;
    }

    const id_str = target[prefix.len..];
    const id = std.fmt.parseInt(i64, id_str, 10) catch {
        try respondError(request, .bad_request, "Invalid provider ID");
        return;
    };

    app.store.deleteProviderProfile(id) catch {
        try respondError(request, .internal_server_error, "Delete failed");
        return;
    };

    try respondJson(request, "{\"success\":true}");
}

fn handleGetPersonas(
    allocator: std.mem.Allocator,
    app: *App,
    request: *std.http.Server.Request,
) !void {
    const personas = try app.store.listPersonaProfiles(allocator);
    defer {
        for (personas) |p| MemoryStore.freePersonaStrings(allocator, p);
        allocator.free(personas);
    }

    const json = try buildPersonasJson(allocator, personas);
    defer allocator.free(json);

    try respondJson(request, json);
}

fn handlePostPersona(
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

    const profile = parsePersonaInput(allocator, body) catch {
        try respondError(request, .bad_request, "Invalid JSON");
        return;
    };
    defer MemoryStore.freePersonaStrings(allocator, profile);

    const id = app.store.createPersonaProfile(profile) catch {
        try respondError(request, .internal_server_error, "Failed to create");
        return;
    };

    var buf: [64]u8 = undefined;
    const resp = std.fmt.bufPrint(&buf, "{{\"id\":{d}}}", .{id}) catch
        "{\"id\":0}";

    try respondJson(request, resp);
}

fn handleDeletePersona(
    allocator: std.mem.Allocator,
    app: *App,
    request: *std.http.Server.Request,
) !void {
    _ = allocator;
    const target = request.head.target;
    const prefix = "/api/profiles/personas/";

    if (target.len <= prefix.len) {
        try respondError(request, .bad_request, "Missing persona ID");
        return;
    }

    const id_str = target[prefix.len..];
    const id = std.fmt.parseInt(i64, id_str, 10) catch {
        try respondError(request, .bad_request, "Invalid persona ID");
        return;
    };

    app.store.deletePersonaProfile(id) catch {
        try respondError(request, .internal_server_error, "Delete failed");
        return;
    };

    try respondJson(request, "{\"success\":true}");
}

fn handleGetActiveProfiles(
    app: *App,
    request: *std.http.Server.Request,
) !void {
    const provider_id = app.store.getActiveProviderId();
    const persona_id = app.store.getActivePersonaId();

    var buf: [128]u8 = undefined;
    const json = std.fmt.bufPrint(
        &buf,
        "{{\"provider_id\":{s},\"persona_id\":{s}}}",
        .{
            if (provider_id) |p|
                std.fmt.bufPrint(
                    buf[100..],
                    "{d}",
                    .{p},
                ) catch "null"
            else
                "null",
            if (persona_id) |p|
                std.fmt.bufPrint(
                    buf[110..],
                    "{d}",
                    .{p},
                ) catch "null"
            else
                "null",
        },
    ) catch "{\"provider_id\":null,\"persona_id\":null}";

    try respondJson(request, json);
}

fn handlePostActiveProfiles(
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

    var parsed = std.json.parseFromSlice(
        std.json.Value,
        allocator,
        body,
        .{},
    ) catch {
        try respondError(request, .bad_request, "Invalid JSON");
        return;
    };
    defer parsed.deinit();

    if (parsed.value != .object) {
        try respondError(request, .bad_request, "Invalid JSON");
        return;
    }
    const root = parsed.value.object;

    var provider_changed = false;
    var persona_changed = false;

    if (root.get("provider_id")) |pv| {
        const new_id: ?i64 = switch (pv) {
            .integer => |i| i,
            .null => null,
            else => {
                try respondError(request, .bad_request, "Invalid provider_id");
                return;
            },
        };
        app.store.setActiveProviderId(new_id) catch {};
        provider_changed = true;
    }

    if (root.get("persona_id")) |pv| {
        const new_id: ?i64 = switch (pv) {
            .integer => |i| i,
            .null => null,
            else => {
                try respondError(request, .bad_request, "Invalid persona_id");
                return;
            },
        };
        app.store.setActivePersonaId(new_id) catch {};
        persona_changed = true;
    }

    if (provider_changed) {
        app.reloadActiveProvider(allocator) catch |err| {
            app.cli.msg(.wrn, "Provider reload failed: {}", .{err});
        };
    }

    if (persona_changed) {
        app.reloadActivePersona(allocator) catch |err| {
            app.cli.msg(.wrn, "Persona reload failed: {}", .{err});
        };
    }

    try respondJson(request, "{\"success\":true}");
}

const ProviderInput = struct {
    name: []u8,
    ollama_url: []u8,
    model: []u8,
};

fn parseProviderInput(
    allocator: std.mem.Allocator,
    body: []const u8,
) !ProviderInput {
    var parsed = try std.json.parseFromSlice(
        std.json.Value,
        allocator,
        body,
        .{},
    );
    defer parsed.deinit();

    if (parsed.value != .object) return error.InvalidJson;
    const root = parsed.value.object;

    const name_v = root.get("name") orelse return error.MissingName;
    const url_v = root.get("ollama_url") orelse return error.MissingUrl;
    const model_v = root.get("model") orelse return error.MissingModel;

    if (name_v != .string) return error.InvalidName;
    if (url_v != .string) return error.InvalidUrl;
    if (model_v != .string) return error.InvalidModel;

    return .{
        .name = try allocator.dupe(u8, name_v.string),
        .ollama_url = try allocator.dupe(u8, url_v.string),
        .model = try allocator.dupe(u8, model_v.string),
    };
}

fn parsePersonaInput(
    allocator: std.mem.Allocator,
    body: []const u8,
) !Types.PersonaProfile {
    var parsed = try std.json.parseFromSlice(
        std.json.Value,
        allocator,
        body,
        .{},
    );
    defer parsed.deinit();

    if (parsed.value != .object) return error.InvalidJson;
    const root = parsed.value.object;

    const name_v = root.get("name") orelse return error.MissingName;
    const ai_name_v = root.get("ai_name") orelse return error.MissingAiName;
    const tone_v = root.get("tone") orelse return error.MissingTone;

    if (name_v != .string) return error.InvalidName;
    if (ai_name_v != .string) return error.InvalidAiName;
    if (tone_v != .string) return error.InvalidTone;

    return .{
        .name = try allocator.dupe(u8, name_v.string),
        .ai_name = try allocator.dupe(u8, ai_name_v.string),
        .tone = try allocator.dupe(u8, tone_v.string),
        .llm_chat = .{
            .temperature = getJsonFloat(root, "llm_chat_temp") orelse 0.7,
            .max_tokens = getJsonU32(root, "llm_chat_tokens") orelse 256,
        },
        .llm_reflection = .{
            .temperature = getJsonFloat(root, "llm_reflect_temp") orelse 0.2,
            .max_tokens = getJsonU32(root, "llm_reflect_tokens") orelse 512,
        },
        .llm_idle = .{
            .temperature = getJsonFloat(root, "llm_idle_temp") orelse 0.4,
            .max_tokens = getJsonU32(root, "llm_idle_tokens") orelse 160,
        },
        .llm_episode = .{
            .temperature = getJsonFloat(root, "llm_episode_temp") orelse 0.2,
            .max_tokens = getJsonU32(root, "llm_episode_tokens") orelse 512,
        },
        .conf_user_notes = getJsonFloat(root, "conf_user_notes") orelse 0.7,
        .conf_episodes = getJsonFloat(root, "conf_episodes") orelse 0.85,
        .conf_idle = getJsonFloat(root, "conf_idle") orelse 0.55,
        .conf_governor = getJsonFloat(root, "conf_governor") orelse 0.6,
    };
}

fn getJsonFloat(
    obj: std.json.ObjectMap,
    key: []const u8,
) ?f32 {
    const val = obj.get(key) orelse return null;
    return switch (val) {
        .float => @floatCast(val.float),
        .integer => @floatFromInt(val.integer),
        else => null,
    };
}

fn getJsonU32(
    obj: std.json.ObjectMap,
    key: []const u8,
) ?u32 {
    const val = obj.get(key) orelse return null;
    return switch (val) {
        .integer => @intCast(val.integer),
        else => null,
    };
}

fn buildProvidersJson(
    allocator: std.mem.Allocator,
    providers: []const Types.ProviderProfile,
) ![]u8 {
    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(allocator);

    try out.appendSlice(allocator, "{\"providers\":[");

    for (providers, 0..) |p, i| {
        if (i > 0) try out.append(allocator, ',');

        try out.writer(allocator).print(
            "{{\"id\":{d},\"name\":\"{s}\",\"ollama_url\":\"{s}\"," ++
                "\"model\":\"{s}\",\"created_at_ms\":{d}}}",
            .{ p.id, p.name, p.ollama_url, p.model, p.created_at_ms },
        );
    }

    try out.appendSlice(allocator, "]}");
    return out.toOwnedSlice(allocator);
}

fn buildPersonasJson(
    allocator: std.mem.Allocator,
    personas: []const Types.PersonaProfile,
) ![]u8 {
    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(allocator);

    try out.appendSlice(allocator, "{\"personas\":[");

    for (personas, 0..) |p, i| {
        if (i > 0) try out.append(allocator, ',');

        try out.writer(allocator).print(
            "{{\"id\":{d},\"name\":\"{s}\",\"ai_name\":\"{s}\"," ++
                "\"tone\":\"{s}\",\"llm_chat_temp\":{d:.2}," ++
                "\"llm_chat_tokens\":{d},\"llm_reflect_temp\":{d:.2}," ++
                "\"llm_reflect_tokens\":{d},\"llm_idle_temp\":{d:.2}," ++
                "\"llm_idle_tokens\":{d},\"llm_episode_temp\":{d:.2}," ++
                "\"llm_episode_tokens\":{d},\"conf_user_notes\":{d:.2}," ++
                "\"conf_episodes\":{d:.2},\"conf_idle\":{d:.2}," ++
                "\"conf_governor\":{d:.2},\"created_at_ms\":{d}}}",
            .{
                p.id,
                p.name,
                p.ai_name,
                p.tone,
                p.llm_chat.temperature,
                p.llm_chat.max_tokens,
                p.llm_reflection.temperature,
                p.llm_reflection.max_tokens,
                p.llm_idle.temperature,
                p.llm_idle.max_tokens,
                p.llm_episode.temperature,
                p.llm_episode.max_tokens,
                p.conf_user_notes,
                p.conf_episodes,
                p.conf_idle,
                p.conf_governor,
                p.created_at_ms,
            },
        );
    }

    try out.appendSlice(allocator, "]}");
    return out.toOwnedSlice(allocator);
}

const WEB_ROOT = "web/dist";
const MAX_STATIC_FILE_SIZE = 10 * 1024 * 1024;

fn handleStaticFile(
    allocator: std.mem.Allocator,
    request: *std.http.Server.Request,
) !void {
    const target = request.head.target;

    const clean_path = sanitizePath(target) orelse {
        try respondError(request, .bad_request, "Invalid path");
        return;
    };

    const file_path = std.fs.path.join(allocator, &.{ WEB_ROOT, clean_path }) catch {
        try serveIndexHtml(allocator, request);
        return;
    };
    defer allocator.free(file_path);

    const content = std.fs.cwd().readFileAlloc(
        allocator,
        file_path,
        MAX_STATIC_FILE_SIZE,
    ) catch {
        try serveIndexHtml(allocator, request);
        return;
    };
    defer allocator.free(content);

    const mime = getMimeType(file_path);
    try respondWithMime(request, content, mime);
}

fn sanitizePath(path: []const u8) ?[]const u8 {
    var clean = path;
    if (std.mem.indexOf(u8, path, "?")) |idx| {
        clean = path[0..idx];
    }

    if (std.mem.indexOf(u8, clean, "..") != null) return null;

    if (clean.len == 0 or std.mem.eql(u8, clean, "/")) {
        return "index.html";
    }

    return if (clean[0] == '/') clean[1..] else clean;
}

fn getMimeType(path: []const u8) []const u8 {
    const ext = std.fs.path.extension(path);

    if (std.mem.eql(u8, ext, ".html")) return "text/html; charset=utf-8";
    if (std.mem.eql(u8, ext, ".css")) return "text/css; charset=utf-8";
    if (std.mem.eql(u8, ext, ".js")) return "application/javascript";
    if (std.mem.eql(u8, ext, ".json")) return "application/json";
    if (std.mem.eql(u8, ext, ".png")) return "image/png";
    if (std.mem.eql(u8, ext, ".jpg")) return "image/jpeg";
    if (std.mem.eql(u8, ext, ".jpeg")) return "image/jpeg";
    if (std.mem.eql(u8, ext, ".gif")) return "image/gif";
    if (std.mem.eql(u8, ext, ".svg")) return "image/svg+xml";
    if (std.mem.eql(u8, ext, ".ico")) return "image/x-icon";
    if (std.mem.eql(u8, ext, ".woff")) return "font/woff";
    if (std.mem.eql(u8, ext, ".woff2")) return "font/woff2";
    if (std.mem.eql(u8, ext, ".ttf")) return "font/ttf";
    if (std.mem.eql(u8, ext, ".map")) return "application/json";

    return "application/octet-stream";
}

fn serveIndexHtml(
    allocator: std.mem.Allocator,
    request: *std.http.Server.Request,
) !void {
    const index_path = std.fs.path.join(
        allocator,
        &.{ WEB_ROOT, "index.html" },
    ) catch {
        try respondError(request, .not_found, "index.html not found");
        return;
    };
    defer allocator.free(index_path);

    const content = std.fs.cwd().readFileAlloc(
        allocator,
        index_path,
        1 * 1024 * 1024,
    ) catch {
        try respondError(request, .not_found, "index.html not found");
        return;
    };
    defer allocator.free(content);

    try respondWithMime(request, content, "text/html; charset=utf-8");
}

fn respondWithMime(
    request: *std.http.Server.Request,
    body: []const u8,
    mime: []const u8,
) !void {
    try request.respond(body, .{
        .status = .ok,
        .extra_headers = &.{
            .{ .name = "Content-Type", .value = mime },
            .{ .name = "Access-Control-Allow-Origin", .value = "*" },
            .{ .name = "Cache-Control", .value = "public, max-age=3600" },
        },
    });
}
