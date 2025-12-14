const std = @import("std");
const Types = @import("Types.zig");
const MemoryPolicy = @import("MemoryPolicy.zig").MemoryPolicy;

pub const MemoryStoreMock = struct {
    messages: std.ArrayList(Types.Message),
    identity: std.ArrayList(Types.IdentityEntry),
    memory: std.ArrayList(Types.MemoryItem),

    next_memory_id: i64 = 1,
    episode_cutoff_index: usize = 0,
    time_offset_ms: i64 = 0,
    last_user_msg_ms: i64 = 0,
    last_idle_think_ms: i64 = 0,

    pub fn init(allocator: std.mem.Allocator) MemoryStoreMock {
        var s = MemoryStoreMock{
            .messages = .empty,
            .identity = .empty,
            .memory = .empty,
            .next_memory_id = 1,
        };

        const tone_val = "helpful, concise, grounded";
        const contract_val =
            "Memory is read-only unless the user explicitly asks " ++
            "to store/update something.";
        s.addIdentityEntry(allocator, "tone", tone_val) catch {};
        s.addIdentityEntry(allocator, "memory_contract", contract_val) catch {};

        return s;
    }

    pub fn deinit(self: *MemoryStoreMock, allocator: std.mem.Allocator) void {
        for (self.messages.items) |m| allocator.free(@constCast(m.content));
        self.messages.deinit(allocator);

        for (self.identity.items) |e| {
            allocator.free(@constCast(e.key));
            allocator.free(@constCast(e.value));
        }
        self.identity.deinit(allocator);

        for (self.memory.items) |m| {
            allocator.free(@constCast(m.subject));
            allocator.free(@constCast(m.predicate));
            allocator.free(@constCast(m.object));
        }
        self.memory.deinit(allocator);
    }

    pub fn nowMs(self: *MemoryStoreMock) i64 {
        return std.time.milliTimestamp() + self.time_offset_ms;
    }

    pub fn advanceTimeHours(self: *MemoryStoreMock, hours: i64) void {
        self.time_offset_ms += hours * 60 * 60 * 1000;
    }

    pub fn getLastUserMsgMs(self: *MemoryStoreMock) i64 {
        return self.last_user_msg_ms;
    }

    pub fn getLastIdleThinkMs(self: *MemoryStoreMock) i64 {
        return self.last_idle_think_ms;
    }

    pub fn setLastIdleThinkMs(self: *MemoryStoreMock, ms: i64) void {
        self.last_idle_think_ms = ms;
    }

    pub fn countMessagesSinceCutoff(self: *MemoryStoreMock) usize {
        const total = self.messages.items.len;
        if (self.episode_cutoff_index > total) return 0;
        return total - self.episode_cutoff_index;
    }

    pub fn advanceTimeMinutes(self: *MemoryStoreMock, minutes: i64) void {
        self.time_offset_ms += minutes * 60 * 1000;
    }

    pub fn insertMessage(
        self: *MemoryStoreMock,
        allocator: std.mem.Allocator,
        role: Types.Role,
        content: []const u8,
    ) !void {
        const now = self.nowMs();
        try self.messages.append(allocator, .{
            .role = role,
            .content = try allocator.dupe(u8, content),
            .created_at_ms = now,
        });
        if (role == .user) self.last_user_msg_ms = now;
    }

    pub fn loadRecentMessages(
        self: *MemoryStoreMock,
        allocator: std.mem.Allocator,
        max_count: usize,
    ) ![]Types.Message {
        const total = self.messages.items.len;
        const n = if (total < max_count) total else max_count;

        const out = try allocator.alloc(Types.Message, n);
        const start = total - n;
        for (out, 0..) |*dst, i| dst.* = self.messages.items[start + i];
        return out;
    }

    pub fn loadAllMessages(
        self: *MemoryStoreMock,
        allocator: std.mem.Allocator,
    ) ![]Types.Message {
        const out = try allocator.alloc(Types.Message, self.messages.items.len);
        for (out, 0..) |*dst, i| dst.* = self.messages.items[i];
        return out;
    }

    pub fn loadMessagesSince(
        self: *MemoryStoreMock,
        allocator: std.mem.Allocator,
        since_ms: i64,
    ) ![]Types.Message {
        var count: usize = 0;
        for (self.messages.items) |m| {
            if (m.created_at_ms >= since_ms) count += 1;
        }

        const out = try allocator.alloc(Types.Message, count);
        var j: usize = 0;
        for (self.messages.items) |m| {
            if (m.created_at_ms >= since_ms) {
                out[j] = m;
                j += 1;
            }
        }
        return out;
    }

    pub fn addIdentityEntry(
        self: *MemoryStoreMock,
        allocator: std.mem.Allocator,
        key: []const u8,
        value: []const u8,
    ) !void {
        try self.identity.append(allocator, .{
            .key = try allocator.dupe(u8, key),
            .value = try allocator.dupe(u8, value),
        });
    }

    pub fn loadIdentityCore(
        self: *MemoryStoreMock,
        allocator: std.mem.Allocator,
    ) ![]Types.IdentityEntry {
        const out = try allocator.alloc(
            Types.IdentityEntry,
            self.identity.items.len,
        );
        for (out, 0..) |*dst, i| dst.* = self.identity.items[i];
        return out;
    }

    pub fn addMemory(
        self: *MemoryStoreMock,
        allocator: std.mem.Allocator,
        item: Types.MemoryItem,
    ) !i64 {
        const now = self.nowMs();
        var m = item;

        m.id = self.next_memory_id;
        self.next_memory_id += 1;

        m.created_at_ms = now;
        m.updated_at_ms = now;

        m.subject = try allocator.dupe(u8, m.subject);
        m.predicate = try allocator.dupe(u8, m.predicate);
        m.object = try allocator.dupe(u8, m.object);

        try self.memory.append(allocator, m);
        return m.id;
    }

    pub fn loadMemoryItems(
        self: *MemoryStoreMock,
        allocator: std.mem.Allocator,
        max_count: usize,
    ) ![]Types.MemoryItem {
        var tmp: std.ArrayList(Types.MemoryItem) = .empty;
        defer tmp.deinit(allocator);

        var i: usize = self.memory.items.len;
        while (i > 0 and tmp.items.len < max_count) {
            i -= 1;
            const m = self.memory.items[i];
            if (!m.is_active) continue;
            try tmp.append(allocator, m);
        }

        const out = try allocator.alloc(Types.MemoryItem, tmp.items.len);
        var j: usize = 0;
        while (j < tmp.items.len) : (j += 1) {
            out[j] = tmp.items[tmp.items.len - 1 - j];
        }
        return out;
    }

    pub fn loadAllMemoryItems(
        self: *MemoryStoreMock,
        allocator: std.mem.Allocator,
    ) ![]Types.MemoryItem {
        const out = try allocator.alloc(
            Types.MemoryItem,
            self.memory.items.len,
        );
        for (out, 0..) |*dst, i| dst.* = self.memory.items[i];
        return out;
    }

    pub fn loadMemoryCandidates(
        self: *MemoryStoreMock,
        allocator: std.mem.Allocator,
        max_count: usize,
    ) ![]Types.MemoryItem {
        return self.loadMemoryItems(allocator, max_count);
    }

    pub fn hasActiveMemoryExact(
        self: *MemoryStoreMock,
        kind: Types.MemoryKind,
        subject: []const u8,
        predicate: []const u8,
        object: []const u8,
    ) bool {
        for (self.memory.items) |m| {
            if (!m.is_active) continue;
            if (m.kind != kind) continue;
            if (!std.mem.eql(u8, m.subject, subject)) continue;
            if (!std.mem.eql(u8, m.predicate, predicate)) continue;
            if (!std.mem.eql(u8, m.object, object)) continue;
            return true;
        }
        return false;
    }

    pub fn addMemoryGoverned(
        self: *MemoryStoreMock,
        allocator: std.mem.Allocator,
        policy: MemoryPolicy,
        item: Types.MemoryItem,
    ) !i64 {
        const id = try self.addMemory(allocator, item);
        self.resolveConflicts(policy, id);
        return id;
    }

    fn resolveConflicts(
        self: *MemoryStoreMock,
        policy: MemoryPolicy,
        new_id: i64,
    ) void {
        const new_idx_opt = self.findMemoryIndexById(new_id);
        if (new_idx_opt == null) return;
        const new_idx = new_idx_opt.?;
        var new_item = &self.memory.items[new_idx];
        if (!new_item.is_active) return;

        if (std.mem.eql(u8, new_item.predicate, "says")) return;
        if (std.mem.eql(u8, new_item.subject, "episode")) return;

        for (self.memory.items, 0..) |*old_item, i| {
            if (i == new_idx) continue;
            if (!old_item.is_active) continue;
            if (old_item.kind != new_item.kind) continue;
            if (!std.mem.eql(u8, old_item.subject, new_item.subject)) continue;
            if (!std.mem.eql(u8, old_item.predicate, new_item.predicate)) continue;

            if (std.mem.eql(u8, old_item.object, new_item.object)) continue;

            const old_conf = old_item.confidence;
            const new_conf = new_item.confidence;

            if (new_conf + policy.epsilon >= old_conf) {
                old_item.is_active = false;
                old_item.updated_at_ms = self.nowMs();
            } else {
                new_item.is_active = false;
                new_item.updated_at_ms = self.nowMs();
                break;
            }
        }
    }

    fn findMemoryIndexById(self: *MemoryStoreMock, id: i64) ?usize {
        for (self.memory.items, 0..) |m, i| {
            if (m.id == id) return i;
        }
        return null;
    }

    pub fn decayMemory(
        self: *MemoryStoreMock,
        policy: MemoryPolicy,
        now_ms: i64,
    ) void {
        for (self.memory.items) |*m| {
            if (!m.is_active) continue;

            const age_ms = now_ms - m.updated_at_ms;
            const decayed = policy.decayConfidence(m.confidence, age_ms);

            if (@abs(decayed - m.confidence) > policy.epsilon) {
                m.confidence = decayed;
                m.updated_at_ms = now_ms;
            }

            if (m.confidence < policy.deactivate_below) {
                m.is_active = false;
                m.updated_at_ms = now_ms;
            }
        }
    }

    pub fn loadMessagesSinceCutoff(
        self: *MemoryStoreMock,
        allocator: std.mem.Allocator,
        max_count: usize,
    ) ![]Types.Message {
        const total = self.messages.items.len;
        const start =
            if (self.episode_cutoff_index > total)
                total
            else
                self.episode_cutoff_index;

        const available = total - start;
        const n = if (available < max_count) available else max_count;

        const out = try allocator.alloc(Types.Message, n);
        for (out, 0..) |*dst, i| dst.* = self.messages.items[start + i];
        return out;
    }

    pub fn advanceEpisodeCutoffToEnd(self: *MemoryStoreMock) void {
        self.episode_cutoff_index = self.messages.items.len;
    }

    pub fn getEpisodeCutoffIndex(self: *MemoryStoreMock) usize {
        return self.episode_cutoff_index;
    }

    pub fn lastActiveMemoryTimeForKey(
        self: *MemoryStoreMock,
        kind: Types.MemoryKind,
        subject: []const u8,
        predicate: []const u8,
    ) ?i64 {
        var best: ?i64 = null;
        for (self.memory.items) |m| {
            if (!m.is_active) continue;
            if (m.kind != kind) continue;
            if (!std.mem.eql(u8, m.subject, subject)) continue;
            if (!std.mem.eql(u8, m.predicate, predicate)) continue;
            if (best == null or m.created_at_ms > best.?) best = m.created_at_ms;
        }
        return best;
    }

    pub fn latestActiveObjectByKey(
        self: *MemoryStoreMock,
        subject: []const u8,
        predicate: []const u8,
    ) ?[]const u8 {
        var best_time: i64 = -1;
        var best_obj: ?[]const u8 = null;

        for (self.memory.items) |m| {
            if (!m.is_active) continue;
            if (!std.mem.eql(u8, m.subject, subject)) continue;
            if (!std.mem.eql(u8, m.predicate, predicate)) continue;

            const t =
                if (m.updated_at_ms > 0)
                    m.updated_at_ms
                else
                    m.created_at_ms;
            if (t > best_time) {
                best_time = t;
                best_obj = m.object;
            }
        }
        return best_obj;
    }
};

test "MemoryStoreMock conflict resolution keeps higher confidence" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var store = MemoryStoreMock.init(allocator);
    defer store.deinit(allocator);

    const policy = MemoryPolicy{};

    _ = try store.addMemoryGoverned(allocator, policy, .{
        .kind = .note,
        .subject = "user",
        .predicate = "intent",
        .object = "wants A",
        .confidence = 0.6,
        .is_active = true,
    });

    _ = try store.addMemoryGoverned(allocator, policy, .{
        .kind = .note,
        .subject = "user",
        .predicate = "intent",
        .object = "wants B",
        .confidence = 0.9,
        .is_active = true,
    });

    var active_count: usize = 0;
    for (store.memory.items) |m| {
        if (m.is_active) active_count += 1;
    }
    try std.testing.expectEqual(@as(usize, 1), active_count);

    const active = try store.loadMemoryItems(allocator, 10);
    defer allocator.free(active);
    try std.testing.expectEqualStrings("wants B", active[0].object);
}

test "Episode cutoff slices messages correctly" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var store = MemoryStoreMock.init(allocator);
    defer store.deinit(allocator);

    try store.insertMessage(allocator, .user, "a");
    try store.insertMessage(allocator, .assistant, "b");
    store.advanceEpisodeCutoffToEnd();
    try store.insertMessage(allocator, .user, "c");

    const slice = try store.loadMessagesSinceCutoff(allocator, 10);
    defer allocator.free(slice);

    try std.testing.expectEqual(@as(usize, 1), slice.len);
    try std.testing.expectEqualStrings("c", slice[0].content);
}
