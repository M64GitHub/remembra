const std = @import("std");
const Types = @import("Types.zig");
const Provider = @import("Provider.zig").Provider;
const Cli = @import("Cli.zig").Cli;

/// A proposed memory operation from the model.
pub const ReflectionProposal = struct {
    action: Action,
    kind: Types.MemoryKind,
    subject: []const u8,
    predicate: []const u8,
    object: []const u8,
    confidence: f32,
};

pub const Action = enum {
    add,
    update,
    deactivate,
};

pub const Reflector = struct {
    pub fn run(
        allocator: std.mem.Allocator,
        provider: *Provider,
        identity: []const Types.IdentityEntry,
        memory: []const Types.MemoryItem,
        recent: []const Types.Message,
        assistant_reply: []const u8,
        allow_memory_ops: bool,
        cli: *Cli,
    ) ![]ReflectionProposal {
        const prompt = try buildReflectionPrompt(
            allocator,
            identity,
            memory,
            recent,
            assistant_reply,
            allow_memory_ops,
        );
        defer allocator.free(prompt);

        cli.msg(.dbg, "[Reflection prompt]:\n{s}", .{prompt});

        const msgs = &[_]Types.Message{
            .{ .role = .system, .content = prompt, .created_at_ms = 0 },
        };

        const json = try provider.chat(allocator, msgs, .{
            .model = "mock-reflection",
            .temperature = 0.2,
            .max_tokens = 512,
        });
        defer allocator.free(json);

        return parseProposals(allocator, json);
    }

    fn buildReflectionPrompt(
        allocator: std.mem.Allocator,
        identity: []const Types.IdentityEntry,
        memory: []const Types.MemoryItem,
        recent: []const Types.Message,
        assistant_reply: []const u8,
        allow_memory_ops: bool,
    ) ![]u8 {
        var out: std.ArrayList(u8) = .empty;
        errdefer out.deinit(allocator);

        try out.appendSlice(allocator,
            \\You are the REFLECTION module of REMEMBRA.
            \\You may PROPOSE memory changes, but you do NOT apply them.
            \\
            \\Rules:
            \\- Only propose changes that were explicitly stated by the user.
            \\- Do not infer preferences or facts.
            \\- Use low confidence unless the user was explicit.
            \\- Output JSON ONLY.
            \\
            \\Schema:
            \\{ "proposals": [
            \\  { "action": "add|update|deactivate",
            \\    "kind": "fact|preference|project|note",
            \\    "subject": "...",
            \\    "predicate": "...",
            \\    "object": "...",
            \\    "confidence": 0.0-1.0 }
            \\] }
            \\
            \\
        );

        if (!allow_memory_ops) {
            try out.appendSlice(allocator,
                \\
                \\IMPORTANT: The user did NOT request memory storage in the latest message.
                \\Output MUST be: { "proposals": [] }
                \\
                \\
            );
        }

        try out.appendSlice(allocator, "IDENTITY:\n");
        for (identity) |e| {
            try out.appendSlice(allocator, "- ");
            try out.appendSlice(allocator, e.key);
            try out.appendSlice(allocator, ": ");
            try out.appendSlice(allocator, e.value);
            try out.append(allocator, '\n');
        }

        try out.appendSlice(allocator, "\nMEMORY:\n");
        for (memory) |m| {
            try out.appendSlice(allocator, "- ");
            try out.appendSlice(allocator, m.subject);
            try out.append(allocator, '.');
            try out.appendSlice(allocator, m.predicate);
            try out.append(allocator, '=');
            try out.appendSlice(allocator, m.object);
            try out.append(allocator, '\n');
        }

        try out.appendSlice(allocator, "\nRECENT MESSAGES:\n");
        for (recent) |m| {
            try out.appendSlice(allocator, Types.roleToStr(m.role));
            try out.appendSlice(allocator, ": ");
            try out.appendSlice(allocator, m.content);
            try out.append(allocator, '\n');
        }

        try out.appendSlice(allocator, "\nASSISTANT REPLY:\n");
        try out.appendSlice(allocator, assistant_reply);
        try out.append(allocator, '\n');

        return out.toOwnedSlice(allocator);
    }

    fn parseProposals(
        allocator: std.mem.Allocator,
        json: []const u8,
    ) ![]ReflectionProposal {
        var parsed = try std.json.parseFromSlice(
            std.json.Value,
            allocator,
            json,
            .{},
        );
        defer parsed.deinit();

        if (parsed.value != .object) return error.InvalidReflectionJson;
        const root = parsed.value.object;

        const props_v = root.get("proposals") orelse
            return error.InvalidReflectionJson;

        if (props_v != .array) return error.InvalidReflectionJson;

        var out: std.ArrayList(ReflectionProposal) = .empty;
        errdefer out.deinit(allocator);

        for (props_v.array.items) |item| {
            if (item != .object) continue;
            const o = item.object;

            const action = parseAction(o.get("action") orelse continue);
            const kind = parseKind(o.get("kind") orelse continue);

            const subject =
                try dupStr(allocator, o.get("subject") orelse continue);

            const predicate = try dupStr(allocator, o.get("predicate") orelse
                continue);

            const object = try dupStr(allocator, o.get("object") orelse
                continue);

            const conf_v = o.get("confidence") orelse continue;
            const confidence: f32 = switch (conf_v) {
                .float => @floatCast(conf_v.float),
                .integer => @floatFromInt(conf_v.integer),
                else => 0.5,
            };

            try out.append(allocator, .{
                .action = action,
                .kind = kind,
                .subject = subject,
                .predicate = predicate,
                .object = object,
                .confidence = confidence,
            });
        }

        return out.toOwnedSlice(allocator);
    }

    fn dupStr(allocator: std.mem.Allocator, v: std.json.Value) ![]const u8 {
        if (v != .string) return error.InvalidReflectionJson;
        return allocator.dupe(u8, v.string);
    }

    fn parseAction(v: std.json.Value) Action {
        if (v != .string) return .add;
        if (std.mem.eql(u8, v.string, "update")) return .update;
        if (std.mem.eql(u8, v.string, "deactivate")) return .deactivate;
        return .add;
    }

    fn parseKind(v: std.json.Value) Types.MemoryKind {
        if (v != .string) return .note;
        if (std.mem.eql(u8, v.string, "fact")) return .fact;
        if (std.mem.eql(u8, v.string, "preference")) return .preference;
        if (std.mem.eql(u8, v.string, "project")) return .project;
        return .note;
    }
};
