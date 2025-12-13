const std = @import("std");
const Types = @import("Types.zig");
const ReflectionProposal = @import("Reflector.zig").ReflectionProposal;
const MemoryStoreMock = @import("MemoryStoreMock.zig").MemoryStoreMock;
const MemoryPolicy = @import("MemoryPolicy.zig").MemoryPolicy;
const Cli = @import("Cli.zig").Cli;

pub const Governor = struct {
    pub fn apply(
        store: *MemoryStoreMock,
        policy: MemoryPolicy,
        proposals: []const ReflectionProposal,
        cli: *Cli,
    ) !void {
        const now = std.time.milliTimestamp();

        for (proposals) |p| {
            if (!isAllowed(p)) {
                cli.msg(.wrn, "[Governor] rejected: {s}.{s}={s}", .{ p.subject, p.predicate, p.object });
                continue;
            }

            // Rate limit: 30s per (kind, subject, predicate) key
            if (store.lastActiveMemoryTimeForKey(p.kind, p.subject, p.predicate)) |t| {
                if (now - t < 30_000) {
                    cli.msg(.wrn, "[Governor] rate-limited key {s}.{s} (wait {d}s)", .{
                        p.subject,
                        p.predicate,
                        @divFloor(30_000 - (now - t), 1000),
                    });
                    continue;
                }
            }

            // Dedupe check
            if (store.hasActiveMemoryExact(p.kind, p.subject, p.predicate, p.object)) {
                cli.msg(.inf, "[Governor] dedupe: already stored", .{});
                continue;
            }

            const id = try store.addMemoryGoverned(policy, .{
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
        // Rule 1: Only "add" actions allowed
        if (p.action != .add) return false;

        // Rule 2: Only note kind allowed
        if (p.kind != .note) return false;

        // Rule 3: Confidence must be >= 0.6
        if (p.confidence < 0.6) return false;

        // Rule 4: Subject must be "user" or "self"
        if (!std.mem.eql(u8, p.subject, "user") and
            !std.mem.eql(u8, p.subject, "self"))
            return false;

        // Rule 5: No inferred facts/preferences
        if (std.mem.eql(u8, p.predicate, "likes")) return false;
        if (std.mem.eql(u8, p.predicate, "is")) return false;

        return true;
    }
};
