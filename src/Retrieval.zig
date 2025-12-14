//! Retrieval scoring for memory item selection.

const std = @import("std");
const Types = @import("Types.zig");

pub const Retrieval = struct {
    pub const Params = struct {
        max_total: usize = 12,
        max_per_key: usize = 2,
        max_user_says: usize = 1,
        w_conf: f32 = 0.45,
        w_recency: f32 = 0.35,
        w_relevance: f32 = 0.20,
        recency_half_life_ms: i64 = 3 * 24 * 60 * 60 * 1000,
        min_score: f32 = 0.01,
    };

    const Scored = struct {
        idx: usize,
        score: f32,
        subject: []const u8,
        predicate: []const u8,
    };

    pub fn select(
        allocator: std.mem.Allocator,
        candidates: []const Types.MemoryItem,
        user_input: []const u8,
        now_ms: i64,
        params: Params,
    ) ![]usize {
        var scored: std.ArrayList(Scored) = .empty;
        defer scored.deinit(allocator);

        try scored.ensureTotalCapacity(allocator, candidates.len);

        for (candidates, 0..) |m, i| {
            if (!m.is_active) continue;

            const s = scoreOne(m, user_input, now_ms, params);
            if (s < params.min_score) continue;

            scored.appendAssumeCapacity(.{
                .idx = i,
                .score = s,
                .subject = m.subject,
                .predicate = m.predicate,
            });
        }

        std.mem.sortUnstable(Scored, scored.items, {}, lessThanByScore);

        var selected: std.ArrayList(usize) = .empty;
        errdefer selected.deinit(allocator);
        try selected.ensureTotalCapacity(
            allocator,
            @min(params.max_total, scored.items.len),
        );

        var key_counts = std.AutoHashMap(u64, usize).init(allocator);
        defer key_counts.deinit();

        var user_says_count: usize = 0;

        for (scored.items) |x| {
            if (selected.items.len >= params.max_total) break;

            const subj = x.subject;
            const pred = x.predicate;

            const is_user_says = std.mem.eql(u8, subj, "user") and
                std.mem.eql(u8, pred, "says");
            if (is_user_says) {
                if (user_says_count >= params.max_user_says) continue;
            }

            const key = hashKey(subj, pred);
            const cur = key_counts.get(key) orelse 0;
            if (cur >= params.max_per_key) continue;

            try selected.append(allocator, x.idx);
            try key_counts.put(key, cur + 1);

            if (is_user_says) {
                user_says_count += 1;
            }
        }

        return selected.toOwnedSlice(allocator);
    }

    fn lessThanByScore(_: void, a: Scored, b: Scored) bool {
        return a.score > b.score;
    }

    fn scoreOne(
        m: Types.MemoryItem,
        user_input: []const u8,
        now_ms: i64,
        params: Params,
    ) f32 {
        const conf = clamp01(m.confidence);

        const age_ms = ageMs(m, now_ms);
        const rec = recencyScore(age_ms, params.recency_half_life_ms);

        const rel = relevanceScore(user_input, m.subject, m.predicate, m.object);

        return params.w_conf * conf +
            params.w_recency * rec +
            params.w_relevance * rel;
    }

    fn ageMs(m: Types.MemoryItem, now_ms: i64) i64 {
        const t = if (m.updated_at_ms > 0) m.updated_at_ms else m.created_at_ms;
        const d = now_ms - t;
        return if (d < 0) 0 else d;
    }

    fn recencyScore(age_ms: i64, half_life_ms: i64) f32 {
        if (half_life_ms <= 0) return 0.0;
        const x: f64 = @as(f64, @floatFromInt(age_ms)) /
            @as(f64, @floatFromInt(half_life_ms));
        return @floatCast(std.math.pow(f64, 0.5, x));
    }

    fn relevanceScore(
        user_input: []const u8,
        subject: []const u8,
        predicate: []const u8,
        object: []const u8,
    ) f32 {
        var user_tokens: [32][]const u8 = undefined;
        var mem_tokens: [48][]const u8 = undefined;

        const u_n = tokenize(user_input, &user_tokens);
        const m_n = tokenize3(subject, predicate, object, &mem_tokens);

        if (u_n == 0 or m_n == 0) return 0.0;

        var hits: usize = 0;
        for (user_tokens[0..u_n]) |ut| {
            for (mem_tokens[0..m_n]) |mt| {
                if (eqLower(ut, mt)) {
                    hits += 1;
                    break;
                }
            }
        }

        return clamp01(
            @as(f32, @floatFromInt(hits)) / @as(f32, @floatFromInt(u_n)),
        );
    }

    fn tokenize(input: []const u8, out: *[32][]const u8) usize {
        var n: usize = 0;
        var it = std.mem.tokenizeAny(u8, input, " \t\r\n,.;:!?()[]{}<>\"'");
        while (it.next()) |tok| {
            if (tok.len < 2) continue;
            out[n] = tok;
            n += 1;
            if (n >= out.len) break;
        }
        return n;
    }

    fn tokenize3(
        a: []const u8,
        b: []const u8,
        c: []const u8,
        out: *[48][]const u8,
    ) usize {
        var n: usize = 0;
        n += tokenizeInto(a, out, n);
        n += tokenizeInto(b, out, n);
        n += tokenizeInto(c, out, n);
        return n;
    }

    fn tokenizeInto(
        input: []const u8,
        out: *[48][]const u8,
        start: usize,
    ) usize {
        var n: usize = 0;
        var it = std.mem.tokenizeAny(u8, input, " \t\r\n,.;:!?()[]{}<>\"'");
        while (it.next()) |tok| {
            if (tok.len < 2) continue;
            const idx = start + n;
            if (idx >= out.len) break;
            out[idx] = tok;
            n += 1;
        }
        return n;
    }

    fn eqLower(a: []const u8, b: []const u8) bool {
        if (a.len != b.len) return false;
        for (a, b) |ca, cb| {
            if (std.ascii.toLower(ca) != std.ascii.toLower(cb)) return false;
        }
        return true;
    }

    fn clamp01(x: f32) f32 {
        if (x < 0.0) return 0.0;
        if (x > 1.0) return 1.0;
        return x;
    }

    fn hashKey(subject: []const u8, predicate: []const u8) u64 {
        var h = std.hash.Wyhash.init(0);
        h.update(subject);
        h.update("|");
        h.update(predicate);
        return h.final();
    }
};

test "Retrieval prefers higher confidence when relevance equal" {
    const A = std.testing.allocator;
    const now: i64 = 1_000_000;

    const items = [_]Types.MemoryItem{
        .{
            .id = 1,
            .kind = .note,
            .subject = "user",
            .predicate = "intent",
            .object = "likes neon",
            .confidence = 0.9,
            .is_active = true,
            .created_at_ms = now - 1000,
            .updated_at_ms = now - 1000,
        },
        .{
            .id = 2,
            .kind = .note,
            .subject = "user",
            .predicate = "intent",
            .object = "likes neon",
            .confidence = 0.4,
            .is_active = true,
            .created_at_ms = now - 1000,
            .updated_at_ms = now - 1000,
        },
    };

    const idxs = try Retrieval.select(A, &items, "neon", now, .{
        .max_total = 2,
    });
    defer A.free(idxs);

    try std.testing.expectEqual(@as(usize, 0), idxs[0]);
}

test "Retrieval caps user.says" {
    const A = std.testing.allocator;
    const now: i64 = 1_000_000;

    const items = [_]Types.MemoryItem{
        .{
            .id = 1,
            .kind = .note,
            .subject = "user",
            .predicate = "says",
            .object = "alpha beta",
            .confidence = 0.9,
            .is_active = true,
            .created_at_ms = now - 1000,
            .updated_at_ms = now - 1000,
        },
        .{
            .id = 2,
            .kind = .note,
            .subject = "user",
            .predicate = "says",
            .object = "beta gamma",
            .confidence = 0.9,
            .is_active = true,
            .created_at_ms = now - 900,
            .updated_at_ms = now - 900,
        },
        .{
            .id = 3,
            .kind = .note,
            .subject = "user",
            .predicate = "intent",
            .object = "wants governed memory",
            .confidence = 0.6,
            .is_active = true,
            .created_at_ms = now - 800,
            .updated_at_ms = now - 800,
        },
    };

    const idxs = try Retrieval.select(A, &items, "beta", now, .{
        .max_total = 10,
        .max_user_says = 1,
    });
    defer A.free(idxs);

    var says_count: usize = 0;
    for (idxs) |i| {
        const is_says = std.mem.eql(u8, items[i].subject, "user") and
            std.mem.eql(u8, items[i].predicate, "says");
        if (is_says) says_count += 1;
    }
    try std.testing.expectEqual(@as(usize, 1), says_count);
}

test "Retrieval caps per key" {
    const A = std.testing.allocator;
    const now: i64 = 1_000_000;

    const items = [_]Types.MemoryItem{
        .{
            .id = 1,
            .kind = .fact,
            .subject = "user",
            .predicate = "likes",
            .object = "cats",
            .confidence = 0.9,
            .is_active = true,
            .created_at_ms = now - 100,
            .updated_at_ms = now - 100,
        },
        .{
            .id = 2,
            .kind = .fact,
            .subject = "user",
            .predicate = "likes",
            .object = "dogs",
            .confidence = 0.85,
            .is_active = true,
            .created_at_ms = now - 200,
            .updated_at_ms = now - 200,
        },
        .{
            .id = 3,
            .kind = .fact,
            .subject = "user",
            .predicate = "likes",
            .object = "birds",
            .confidence = 0.8,
            .is_active = true,
            .created_at_ms = now - 300,
            .updated_at_ms = now - 300,
        },
    };

    const idxs = try Retrieval.select(A, &items, "pets", now, .{
        .max_total = 10,
        .max_per_key = 2,
    });
    defer A.free(idxs);

    try std.testing.expectEqual(@as(usize, 2), idxs.len);
}

test "Retrieval relevance scoring favors matching tokens" {
    const A = std.testing.allocator;
    const now: i64 = 1_000_000;

    const items = [_]Types.MemoryItem{
        .{
            .id = 1,
            .kind = .note,
            .subject = "user",
            .predicate = "intent",
            .object = "unrelated stuff",
            .confidence = 0.9,
            .is_active = true,
            .created_at_ms = now - 100,
            .updated_at_ms = now - 100,
        },
        .{
            .id = 2,
            .kind = .note,
            .subject = "user",
            .predicate = "intent",
            .object = "likes coffee morning",
            .confidence = 0.5,
            .is_active = true,
            .created_at_ms = now - 100,
            .updated_at_ms = now - 100,
        },
    };

    const idxs = try Retrieval.select(A, &items, "coffee morning", now, .{
        .max_total = 10,
        .w_relevance = 0.6,
        .w_conf = 0.2,
        .w_recency = 0.2,
    });
    defer A.free(idxs);

    try std.testing.expect(idxs.len >= 1);
    try std.testing.expectEqual(@as(usize, 1), idxs[0]);
}
