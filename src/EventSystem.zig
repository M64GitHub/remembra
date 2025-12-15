//! Event emission and persistence for REMEMBRA observability.

const std = @import("std");
const MemoryStore = @import("MemoryStoreSqlite.zig");
const EventKind = MemoryStore.EventKind;
const Event = MemoryStore.Event;

pub const EventSystem = struct {
    store: *MemoryStore.MemoryStoreSqlite,
    session_id: ?[]const u8,

    pub fn init(
        store: *MemoryStore.MemoryStoreSqlite,
        session_id: ?[]const u8,
    ) EventSystem {
        return .{
            .store = store,
            .session_id = session_id,
        };
    }

    pub fn emit(
        self: *EventSystem,
        kind: EventKind,
        subject: []const u8,
        details: []const u8,
    ) void {
        _ = self.store.insertEvent(
            kind,
            subject,
            details,
            self.session_id,
        ) catch {};
    }

    pub fn emitFmt(
        self: *EventSystem,
        kind: EventKind,
        subject: []const u8,
        comptime fmt: []const u8,
        args: anytype,
    ) void {
        var buf: [1024]u8 = undefined;
        const details = std.fmt.bufPrint(&buf, fmt, args) catch "(fmt error)";
        self.emit(kind, subject, details);
    }

    pub fn query(
        self: *EventSystem,
        allocator: std.mem.Allocator,
        since_ms: ?i64,
        kind_filter: ?EventKind,
        limit: usize,
    ) ![]Event {
        return self.store.queryEvents(allocator, since_ms, kind_filter, limit);
    }
};

pub fn freeEvents(allocator: std.mem.Allocator, events: []Event) void {
    for (events) |e| {
        allocator.free(@constCast(e.subject));
        allocator.free(@constCast(e.details));
        if (e.session_id) |sid| allocator.free(@constCast(sid));
    }
    allocator.free(events);
}
