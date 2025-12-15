const std = @import("std");
const Types = @import("Types.zig");
const ReflectionProposal = @import("Reflector.zig").ReflectionProposal;
const MemoryPolicy = @import("MemoryPolicy.zig").MemoryPolicy;
const Cli = @import("Cli.zig").Cli;
const EventSystem = @import("EventSystem.zig").EventSystem;

pub const Governor = struct {
    pub const Params = struct {
        rate_limit_ms: i64 = 30_000,
        confidence_min: f32 = 0.6,
    };

    const ValidationError = error{
        ActionMustBeAdd,
        ConfidenceTooLow,
        InvalidKind,
        InvalidSubject,
    };

    pub fn apply(
        allocator: std.mem.Allocator,
        store: anytype,
        policy: MemoryPolicy,
        proposals: []const ReflectionProposal,
        cli: *Cli,
        events: *EventSystem,
        params: Params,
    ) !void {
        const now = std.time.milliTimestamp();

        for (proposals) |p| {
            validateProposal(p, params.confidence_min) catch |err| {
                cli.msg(.wrn, "[Governor] rejected: {s}.{s}={s} ({s})", .{
                    p.subject,
                    p.predicate,
                    p.object,
                    @errorName(err),
                });
                events.emitFmt(
                    .governor_blocked,
                    p.subject,
                    "validation: {s}",
                    .{@errorName(err)},
                );
                continue;
            };

            const last_time = store.lastActiveMemoryTimeForKey(
                p.kind,
                p.subject,
                p.predicate,
            );
            if (last_time) |t| {
                if (now - t < params.rate_limit_ms) {
                    cli.msg(
                        .wrn,
                        "[Governor] rate-limited key {s}.{s} (wait {d}s)",
                        .{
                            p.subject,
                            p.predicate,
                            @divFloor(params.rate_limit_ms - (now - t), 1000),
                        },
                    );
                    events.emit(.governor_blocked, p.subject, "rate-limited");
                    continue;
                }
            }

            if (store.hasActiveMemoryExact(
                p.kind,
                p.subject,
                p.predicate,
                p.object,
            )) {
                cli.msg(.inf, "[Governor] dedupe: already stored", .{});
                events.emit(.governor_blocked, p.subject, "duplicate");
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
            events.emitFmt(.governor_accepted, p.subject, "id={d}", .{id});
            events.emitFmt(
                .memory_stored,
                p.subject,
                "{s}.{s}={s}",
                .{ p.subject, p.predicate, p.object },
            );
        }
    }

    fn validateProposal(
        p: ReflectionProposal,
        min_conf: f32,
    ) ValidationError!void {
        if (p.action != .add) return error.ActionMustBeAdd;
        if (p.confidence < min_conf) return error.ConfidenceTooLow;

        const valid_kind = (p.kind == .note) or
            (p.kind == .fact) or
            (p.kind == .preference);
        if (!valid_kind) return error.InvalidKind;

        const valid_subject = std.mem.eql(u8, p.subject, "user") or
            std.mem.eql(u8, p.subject, "self");
        if (!valid_subject) return error.InvalidSubject;
    }
};
