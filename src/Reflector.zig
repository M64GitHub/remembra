const std = @import("std");
const Types = @import("Types.zig");
const Cli = @import("Cli.zig").Cli;
const JsonUtils = @import("JsonUtils.zig");
const LlmParams = @import("ConfigIdentity.zig").LlmParams;

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
        provider: anytype,
        identity: []const Types.IdentityEntry,
        memory: []const Types.MemoryItem,
        recent: []const Types.Message,
        assistant_reply: []const u8,
        allow_memory_ops: bool,
        cli: *Cli,
        llm_params: LlmParams,
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
            .{
                .role = .user,
                .content = "Analyze and output JSON proposals.",
                .created_at_ms = 0,
            },
        };

        const response = try provider.chat(allocator, msgs, .{
            .model = "mock-reflection",
            .temperature = llm_params.temperature,
            .max_tokens = llm_params.max_tokens,
        });
        defer allocator.free(response);

        cli.msg(.dbg, "[Reflector] LLM response: {s}", .{response});

        const extracted = JsonUtils.extractJsonObject(response);
        cli.msg(.dbg, "[Reflector] Extracted JSON: {s}", .{extracted});

        return parseProposals(allocator, extracted) catch {
            cli.msg(.wrn, "[Reflector] Failed to parse JSON", .{});
            return allocator.alloc(ReflectionProposal, 0);
        };
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
            \\SUBJECT RULES (IMPORTANT):
            \\- subject MUST be "user" (facts about the human) or "self" (about AI)
            \\- NEVER use the user's name as subject - always use "user"
            \\- These are canonical identifiers, not personal names
            \\
            \\RULES:
            \\- Only propose changes explicitly stated by the user
            \\- Do not infer preferences or facts
            \\- Use confidence >= 0.7 for explicit statements
            \\- Check existing memory - don't propose duplicates
            \\- Output JSON ONLY, no other text
            \\
            \\SCHEMA:
            \\{ "proposals": [
            \\  { "action": "add",
            \\    "kind": "fact",
            \\    "subject": "user",
            \\    "predicate": "friend",
            \\    "object": "Lala",
            \\    "confidence": 0.8 }
            \\] }
            \\
            \\action: add|update|deactivate
            \\kind: fact|preference|project|note
            \\subject: "user" or "self" ONLY
            \\
            \\EXAMPLES:
            \\- "remember Lala is my friend" -> user.friend=Lala
            \\- "I like coffee" -> user.likes=coffee
            \\- "my name is Mario" -> user.name=Mario
            \\
            \\Empty if nothing to store: { "proposals": [] }
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

            const action_v = o.get("action") orelse continue;
            const kind_v = o.get("kind") orelse continue;
            const subject_v = o.get("subject") orelse continue;
            const predicate_v = o.get("predicate") orelse continue;
            const object_v = o.get("object") orelse continue;
            const conf_v = o.get("confidence") orelse continue;

            if (subject_v != .string) continue;
            if (predicate_v != .string) continue;
            if (object_v != .string) continue;

            const action = parseAction(action_v);
            const kind = parseKind(kind_v);

            const confidence: f32 = switch (conf_v) {
                .float => @floatCast(conf_v.float),
                .integer => @floatFromInt(conf_v.integer),
                else => 0.5,
            };

            try out.append(allocator, .{
                .action = action,
                .kind = kind,
                .subject = try allocator.dupe(u8, subject_v.string),
                .predicate = try allocator.dupe(u8, predicate_v.string),
                .object = try allocator.dupe(u8, object_v.string),
                .confidence = confidence,
            });
        }

        return out.toOwnedSlice(allocator);
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
