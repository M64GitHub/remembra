const std = @import("std");
const Types = @import("Types.zig");
const OpenAiCompat = @import("OpenAiCompat.zig");
const NetClientMock = @import("NetClientMock.zig").NetClientMock;

pub const Provider = struct {
    net: NetClientMock,

    pub fn init() Provider {
        return .{ .net = NetClientMock.init() };
    }

    pub fn deinit(self: *Provider) void {
        self.net.deinit();
    }

    pub fn chat(
        self: *Provider,
        allocator: std.mem.Allocator,
        msgs: []const Types.Message,
        params: Types.ChatParams,
    ) ![]u8 {
        const resp = try self.net.send(allocator, .{
            .messages = msgs,
            .params = params,
        });
        defer allocator.free(resp.body);

        return OpenAiCompat.extractAssistantContent(allocator, resp.body);
    }
};
