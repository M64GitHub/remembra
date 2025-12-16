const std = @import("std");
const Types = @import("Types.zig");
const ReEntryComposer = @import("ReEntryComposer.zig").ReEntryComposer;
const PromptTemplates = @import("ConfigIdentity.zig").PromptTemplates;

pub const PromptBuilder = struct {
    pub fn build(
        allocator: std.mem.Allocator,
        identity: []const Types.IdentityEntry,
        memory: []const Types.MemoryItem,
        recent: []const Types.Message,
        user_input: []const u8,
        now_ms: i64,
        last_user_ms: i64,
        last_episode_summary: ?[]const u8,
        last_idle_thought: ?[]const u8,
        ai_name: []const u8,
        persona_kernel: []const u8,
        prompts: PromptTemplates,
    ) ![]Types.Message {
        var msgs: std.ArrayList(Types.Message) = .empty;
        errdefer msgs.deinit(allocator);

        const system_spine = try buildSystemSpine(
            allocator,
            identity,
            memory,
            now_ms,
            last_user_ms,
            last_episode_summary,
            last_idle_thought,
            ai_name,
            persona_kernel,
            prompts.system_spine,
        );
        errdefer allocator.free(system_spine);

        try msgs.append(allocator, .{
            .role = .system,
            .content = system_spine,
            .created_at_ms = 0,
        });

        for (recent) |m| try msgs.append(allocator, m);

        try msgs.append(allocator, .{
            .role = .user,
            .content = user_input,
            .created_at_ms = 0,
        });

        return msgs.toOwnedSlice(allocator);
    }

    fn buildSystemSpine(
        allocator: std.mem.Allocator,
        identity: []const Types.IdentityEntry,
        memory: []const Types.MemoryItem,
        now_ms: i64,
        last_user_ms: i64,
        last_episode_summary: ?[]const u8,
        last_idle_thought: ?[]const u8,
        ai_name: []const u8,
        persona_kernel: []const u8,
        spine_template: []const u8,
    ) ![]u8 {
        var out: std.ArrayList(u8) = .empty;
        errdefer out.deinit(allocator);

        try out.writer(allocator).print("You are {s}.\n", .{ai_name});
        try out.appendSlice(allocator, spine_template);
        try out.appendSlice(allocator, "\n\n");

        try out.writer(allocator).print(
            "TIME:\n- now_ms={d}\n- last_user_ms={d}\n\n",
            .{ now_ms, last_user_ms },
        );

        const params = ReEntryComposer.Params{};
        const re_ctx = try ReEntryComposer.buildFromParts(
            allocator,
            now_ms,
            last_user_ms,
            last_episode_summary,
            last_idle_thought,
            params,
        );
        if (re_ctx) |ctx| {
            defer allocator.free(ctx);
            try out.appendSlice(allocator, ctx);
        }

        if (identity.len != 0 or persona_kernel.len > 0) {
            try out.appendSlice(allocator, "IDENTITY CORE:\n");
            if (persona_kernel.len > 0) {
                try out.appendSlice(allocator, "- identity: ");
                try out.appendSlice(allocator, ai_name);
                try out.appendSlice(allocator, persona_kernel);
                try out.append(allocator, '\n');
            }
            for (identity) |e| {
                try out.appendSlice(allocator, "- ");
                try out.appendSlice(allocator, e.key);
                try out.appendSlice(allocator, ": ");
                try out.appendSlice(allocator, e.value);
                try out.append(allocator, '\n');
            }
            try out.append(allocator, '\n');
        }

        try out.appendSlice(allocator, "MEMORY (read-only):\n");
        if (memory.len == 0) {
            try out.appendSlice(allocator, "- (none)\n\n");
        } else {
            for (memory) |m| {
                var line_buf: [512]u8 = undefined;
                const line = std.fmt.bufPrint(
                    &line_buf,
                    "- [mem#{d}|{s}|{d:.2}] {s}.{s}={s}\n",
                    .{
                        m.id,
                        Types.kindToStr(m.kind),
                        m.confidence,
                        m.subject,
                        m.predicate,
                        m.object,
                    },
                ) catch "- [mem#?]\n";
                try out.appendSlice(allocator, line);
            }
            try out.append(allocator, '\n');
        }

        return out.toOwnedSlice(allocator);
    }
};
