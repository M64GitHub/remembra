//! Tagged union dispatching chat/chatStream across provider variants.
//! Call sites use provider: anytype; methods below resolve via the tag.

const std = @import("std");
const Types = @import("Types.zig");
const Cli = @import("Cli.zig").Cli;
const ProviderOllama = @import("ProviderOllama.zig").ProviderOllama;
const ProviderOpenRouter =
    @import("ProviderOpenRouter.zig").ProviderOpenRouter;

pub const Provider = union(enum) {
    ollama: ProviderOllama,
    openrouter: ProviderOpenRouter,

    pub fn deinit(
        self: *Provider,
        allocator: std.mem.Allocator,
    ) void {
        switch (self.*) {
            .ollama => |*p| p.deinit(allocator),
            .openrouter => |*p| p.deinit(allocator),
        }
    }

    pub fn typeTag(self: *const Provider) []const u8 {
        return switch (self.*) {
            .ollama => "ollama",
            .openrouter => "openrouter",
        };
    }

    pub fn chat(
        self: *Provider,
        allocator: std.mem.Allocator,
        msgs: []const Types.Message,
        params: Types.ChatParams,
        cli: *Cli,
    ) !Types.ChatResponse {
        return switch (self.*) {
            .ollama => |*p| p.chat(allocator, msgs, params, cli),
            .openrouter => |*p| p.chat(allocator, msgs, params, cli),
        };
    }

    pub fn chatStream(
        self: *Provider,
        allocator: std.mem.Allocator,
        msgs: []const Types.Message,
        params: Types.ChatParams,
        cli: *Cli,
        writer: anytype,
    ) !Types.StreamResult {
        return switch (self.*) {
            .ollama => |*p| p.chatStream(
                allocator,
                msgs,
                params,
                cli,
                writer,
            ),
            .openrouter => |*p| p.chatStream(
                allocator,
                msgs,
                params,
                cli,
                writer,
            ),
        };
    }
};

test "typeTag returns variant name" {
    var p = Provider{
        .ollama = undefined,
    };
    try std.testing.expectEqualStrings("ollama", p.typeTag());
    p = .{ .openrouter = undefined };
    try std.testing.expectEqualStrings("openrouter", p.typeTag());
}
