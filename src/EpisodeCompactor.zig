const std = @import("std");
const Types = @import("Types.zig");
const JsonUtils = @import("JsonUtils.zig");
const LlmParams = @import("config/ConfigIdentity.zig").LlmParams;

pub const EpisodeSummary = struct {
    title: []const u8,
    summary: []const u8,
};

pub const EpisodeCompactor = struct {
    pub fn run(
        allocator: std.mem.Allocator,
        provider: anytype,
        msgs: []const Types.Message,
        llm_params: LlmParams,
    ) !EpisodeSummary {
        const prompt = try buildPrompt(allocator, msgs);
        defer allocator.free(prompt);

        const call_msgs = &[_]Types.Message{
            .{ .role = .system, .content = prompt, .created_at_ms = 0 },
            .{
                .role = .user,
                .content = "Summarize and output JSON.",
                .created_at_ms = 0,
            },
        };

        const response = try provider.chat(allocator, call_msgs, .{
            .model = "mock-episode",
            .temperature = llm_params.temperature,
            .max_tokens = llm_params.max_tokens,
        });
        defer allocator.free(response);

        const extracted = JsonUtils.extractJsonObject(response);
        return parseEpisodeJson(allocator, extracted) catch {
            return .{
                .title = try allocator.dupe(u8, "Episode"),
                .summary = try allocator.dupe(u8, response),
            };
        };
    }

    fn buildPrompt(
        allocator: std.mem.Allocator,
        msgs: []const Types.Message,
    ) ![]u8 {
        var out: std.ArrayList(u8) = .empty;
        errdefer out.deinit(allocator);

        try out.appendSlice(allocator,
            \\EPISODE_COMPACTION
            \\You are the EPISODE COMPACTOR of REMEMBRA.
            \\Summarize the conversation into a compact episode.
            \\Output JSON ONLY.
            \\
            \\Schema:
            \\{ "title": "...", "summary": "..." }
            \\
            \\Conversation:
            \\
        );

        for (msgs) |m| {
            const line = try std.fmt.allocPrint(allocator, "{s}: {s}\n", .{
                Types.roleToStr(m.role),
                m.content,
            });
            defer allocator.free(line);
            try out.appendSlice(allocator, line);
        }

        return out.toOwnedSlice(allocator);
    }

    pub fn parseEpisodeJson(
        allocator: std.mem.Allocator,
        json: []const u8,
    ) !EpisodeSummary {
        var parsed = try std.json.parseFromSlice(
            std.json.Value,
            allocator,
            json,
            .{},
        );
        defer parsed.deinit();

        if (parsed.value != .object) return error.InvalidEpisodeJson;
        const root = parsed.value.object;

        const title_v = root.get("title") orelse
            return error.InvalidEpisodeJson;

        const summary_v = root.get("summary") orelse
            return error.InvalidEpisodeJson;

        if (title_v != .string or summary_v != .string)
            return error.InvalidEpisodeJson;

        return .{
            .title = try allocator.dupe(u8, title_v.string),
            .summary = try allocator.dupe(u8, summary_v.string),
        };
    }
};

test "EpisodeCompactor parses JSON" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const json = "{ \"title\": \"T\", \"summary\": \"S\" }";
    const ep = try EpisodeCompactor.parseEpisodeJson(allocator, json);
    defer {
        allocator.free(ep.title);
        allocator.free(ep.summary);
    }

    try std.testing.expectEqualStrings("T", ep.title);
    try std.testing.expectEqualStrings("S", ep.summary);
}
