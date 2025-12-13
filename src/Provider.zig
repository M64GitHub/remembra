const std = @import("std");
const Types = @import("Types.zig");
const OpenAiCompat = @import("OpenAiCompat.zig");
const NetClientMock = @import("NetClientMock.zig").NetClientMock;

/// Provider is the adapter-agnostic boundary for "get an assistant reply".
/// In Phase 1, it uses NetClientMock (in-memory fake).
pub const Provider = struct {
    allocator: std.mem.Allocator,
    net: NetClientMock,

    pub fn init(allocator: std.mem.Allocator) Provider {
        return .{
            .allocator = allocator,
            .net = NetClientMock.init(allocator),
        };
    }

    pub fn deinit(self: *Provider) void {
        self.net.deinit();
    }

    /// Returns assistant reply content as allocator-owned slice.
    pub fn chat(self: *Provider, allocator: std.mem.Allocator, msgs: []const Types.Message, params: Types.ChatParams) ![]u8 {
        const resp = try self.net.send(.{ .messages = msgs, .params = params });
        defer allocator.free(resp.body);

        return OpenAiCompat.extractAssistantContent(allocator, resp.body);
    }
};
