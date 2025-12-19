//! Event emission via SSE broadcast.

const std = @import("std");
const EventServer = @import("EventServer.zig").EventServer;

pub const EventSystem = struct {
    server: *EventServer,

    pub fn init(server: *EventServer) EventSystem {
        return .{ .server = server };
    }

    pub fn emit(
        self: *EventSystem,
        kind: []const u8,
        subject: []const u8,
        details: []const u8,
    ) void {
        var buf: [1024]u8 = undefined;
        const json = std.fmt.bufPrint(
            &buf,
            "{{\"kind\":\"{s}\",\"subject\":\"{s}\",\"data\":\"{s}\"}}",
            .{ kind, subject, details },
        ) catch return;
        self.server.broadcast(json);
    }

    pub fn emitFmt(
        self: *EventSystem,
        kind: []const u8,
        subject: []const u8,
        comptime fmt: []const u8,
        args: anytype,
    ) void {
        var details_buf: [512]u8 = undefined;
        const details = std.fmt.bufPrint(
            &details_buf,
            fmt,
            args,
        ) catch "(fmt error)";
        self.emit(kind, subject, details);
    }
};
