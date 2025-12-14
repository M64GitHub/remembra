const std = @import("std");
const Types = @import("Types.zig");

pub const NetClientMock = struct {
    pub const Request = struct {
        messages: []const Types.Message,
        params: Types.ChatParams,
    };

    pub const Response = struct {
        status: u16,
        body: []u8,
    };

    pub fn init() NetClientMock {
        return .{};
    }

    pub fn deinit(self: *NetClientMock) void {
        _ = self;
    }

    pub fn send(
        self: *NetClientMock,
        allocator: std.mem.Allocator,
        req: Request,
    ) !Response {
        _ = self;
        _ = req.params;

        if (req.messages.len > 0) {
            if (std.mem.indexOf(
                u8,
                req.messages[0].content,
                "EPISODE_COMPACTION",
            ) != null) {
                const json =
                    \\{ "title": "Episode: governed memory", "summary": "User discussed building a remembering AI architecture with governed memory and constraints." }
                ;
                return .{
                    .status = 200,
                    .body = try openAiWrappedContentEscaped(allocator, json),
                };
            }
        }

        if (req.messages.len > 0) {
            if (std.mem.indexOf(
                u8,
                req.messages[0].content,
                "REFLECTION module",
            ) != null) {
                const full = req.messages[0].content;
                const last_user = lastUserLine(full);

                const explicit =
                    (std.mem.indexOf(u8, last_user, "remember") != null) or
                    (std.mem.indexOf(u8, last_user, "Remember") != null) or
                    (std.mem.indexOf(u8, last_user, "don't forget") != null) or
                    (std.mem.indexOf(u8, last_user, "Do not forget") != null) or
                    (std.mem.indexOf(u8, last_user, "store this") != null) or
                    (std.mem.indexOf(u8, last_user, "save this") != null);

                if (!explicit) {
                    const empty_json = "{\"proposals\":[]}";
                    return .{
                        .status = 200,
                        .body = try openAiWrappedContentEscaped(
                            allocator,
                            empty_json,
                        ),
                    };
                }

                const json =
                    \\{"proposals":[{"action":"add","kind":"note","subject":"user","predicate":"intent","object":"wants governed memory","confidence":0.6}]}
                ;

                return .{
                    .status = 200,
                    .body = try openAiWrappedContentEscaped(allocator, json),
                };
            }
        }

        if (req.messages.len > 0) {
            const content = req.messages[0].content;
            if (std.mem.indexOf(u8, content, "IDLE_MONOLOGUE") != null) {
                const json =
                    \\{ "thought": "Silence is not absence; it is continuity without witness." }
                ;
                return .{
                    .status = 200,
                    .body = try openAiWrappedContentEscaped(allocator, json),
                };
            }
        }

        var last_user: []const u8 = "";
        for (req.messages) |m| {
            if (m.role == .user) last_user = m.content;
        }

        const content = try std.fmt.allocPrint(
            allocator,
            "MOCK_REPLY: {s}",
            .{last_user},
        );
        defer allocator.free(content);

        const wrapped = try openAiWrappedContent(allocator, content);
        return .{ .status = 200, .body = wrapped };
    }

    fn lastUserLine(full: []const u8) []const u8 {
        // Find the last occurrence of "\nuser: "
        const needle = "\nuser: ";
        var last: ?usize = null;

        var pos: usize = 0;
        while (true) {
            const found = std.mem.indexOfPos(u8, full, pos, needle) orelse break;
            last = found + needle.len;
            pos = found + needle.len;
        }

        // Handle case where prompt begins with "user: "
        if (last == null and std.mem.startsWith(u8, full, "user: ")) {
            last = "user: ".len;
        }

        if (last == null) return "";

        // Extract until end of line
        const start = last.?;
        const end = std.mem.indexOfPos(u8, full, start, "\n") orelse full.len;
        return full[start..end];
    }

    fn openAiWrappedContent(
        allocator: std.mem.Allocator,
        content: []const u8,
    ) ![]u8 {
        // Minimal OpenAI-ish response with choices[0].message.content
        return std.fmt.allocPrint(
            allocator,
            "{{\"id\":\"mock\",\"object\":\"chat.completion\",\"choices\":[{{\"index\":0,\"message\":{{\"role\":\"assistant\",\"content\":\"{s}\"}}}}]}}",
            .{content},
        );
    }

    fn openAiWrappedContentEscaped(
        allocator: std.mem.Allocator,
        content: []const u8,
    ) ![]u8 {
        // Escape quotes in content for embedding in JSON string
        var escaped: std.ArrayList(u8) = .empty;
        defer escaped.deinit(allocator);

        for (content) |c| {
            if (c == '"') {
                try escaped.appendSlice(allocator, "\\\"");
            } else if (c == '\\') {
                try escaped.appendSlice(allocator, "\\\\");
            } else {
                try escaped.append(allocator, c);
            }
        }

        return std.fmt.allocPrint(
            allocator,
            "{{\"id\":\"mock\",\"object\":\"chat.completion\",\"choices\":[{{\"index\":0,\"message\":{{\"role\":\"assistant\",\"content\":\"{s}\"}}}}]}}",
            .{escaped.items},
        );
    }
};
