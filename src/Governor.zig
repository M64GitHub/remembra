const std = @import("std");
const Types = @import("Types.zig");
const ReflectionProposal = @import("Reflector.zig").ReflectionProposal;
const MemoryStoreMock = @import("MemoryStoreMock.zig").MemoryStoreMock;
const MemoryPolicy = @import("MemoryPolicy.zig").MemoryPolicy;
const Cli = @import("Cli.zig").Cli;

pub const Governor = struct {
    pub fn apply(
        allocator: std.mem.Allocator,
        store: *MemoryStoreMock,
        policy: MemoryPolicy,
        proposals: []const ReflectionProposal,
        cli: *Cli,
    ) !void {
        const now = std.time.milliTimestamp();

        for (proposals) |p| {
            if (!isAllowed(p)) {
                cli.msg(.wrn, "[Governor] rejected: {s}.{s}={s}", .{
                    p.subject,
                    p.predicate,
                    p.object,
                });
                continue;
            }

            const last_time = store.lastActiveMemoryTimeForKey(
                p.kind,
                p.subject,
                p.predicate,
            );
            if (last_time) |t| {
                if (now - t < 30_000) {
                    cli.msg(.wrn, "[Governor] rate-limited key {s}.{s} (wait {d}s)", .{
                        p.subject,
                        p.predicate,
                        @divFloor(30_000 - (now - t), 1000),
                    });
                    continue;
                }
            }

            if (store.hasActiveMemoryExact(p.kind, p.subject, p.predicate, p.object)) {
                cli.msg(.inf, "[Governor] dedupe: already stored", .{});
                continue;
            }

            const id = try store.addMemoryGoverned(allocator, policy, .{
                .kind = p.kind,
                .subject = p.subject,
                .predicate = p.predicate,
                .object = p.object,
                .confidence = p.confidence,
                .is_active = true,
            });

            cli.msg(.ok, "[Governor] accepted -> stored as [mem#{d}]", .{id});
        }
    }

    fn isAllowed(p: ReflectionProposal) bool {
        if (p.action != .add) return false;
        if (p.kind != .note) return false;
        if (p.confidence < 0.6) return false;

        const valid_subject = std.mem.eql(u8, p.subject, "user") or
            std.mem.eql(u8, p.subject, "self");
        if (!valid_subject) return false;

        if (std.mem.eql(u8, p.predicate, "likes")) return false;
        if (std.mem.eql(u8, p.predicate, "is")) return false;

        return true;
    }
};
