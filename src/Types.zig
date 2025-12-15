const std = @import("std");

/// Core types for REMEMBRA.
///
/// Logical datastore schema (for later adapters, NOT implemented in Phase 0):
///
/// Tables / collections (conceptual):
/// - identity_entries:
///   - id (int)
///   - key (string)          // e.g. "tone", "memory_contract"
///   - value (string)
///   - created_at_ms (int)
///
/// - messages:
///   - id (int)
///   - role (enum: system|user|assistant)
///   - content (string)
///   - created_at_ms (int)
///
/// - memory_items:
///   - id (int)
///   - kind (enum: fact|preference|project|note)
///   - subject (string)      // e.g. "user", "self", "episode"
///   - predicate (string)    // e.g. "likes", "idle_reflection", "summary"
///   - object (string)
///   - confidence (float)
///   - is_active (bool)
///   - created_at_ms (int)
///   - updated_at_ms (int)
///
/// - episode_state:
///   - last_cutoff_message_index (int)
///   - last_chapter_close_ms (int)
///   - last_idle_run_ms (int)
///
/// Notes:
/// - Later phases will add mock providers/stores and then real adapters.
/// - "No HTTP/SQL" means no real networking/database code in the core logic.
///   Mocks are allowed for testing and development in later phases.
pub const Role = enum { system, user, assistant };

pub fn roleToStr(r: Role) []const u8 {
    return switch (r) {
        .system => "system",
        .user => "user",
        .assistant => "assistant",
    };
}

pub const Message = struct {
    role: Role,
    content: []const u8,
    created_at_ms: i64 = 0,
};

pub const IdentityEntry = struct {
    key: []const u8,
    value: []const u8,
};

pub const MemoryKind = enum { fact, preference, project, note };

pub fn kindToStr(k: MemoryKind) []const u8 {
    return switch (k) {
        .fact => "fact",
        .preference => "preference",
        .project => "project",
        .note => "note",
    };
}

pub const MemoryItem = struct {
    /// Store-assigned stable id (mock store auto-increments).
    id: i64 = 0,
    kind: MemoryKind,
    subject: []const u8,
    predicate: []const u8,
    object: []const u8,
    confidence: f32 = 0.5,
    is_active: bool = true,
    created_at_ms: i64 = 0,
    updated_at_ms: i64 = 0,
};

/// Provider-independent chat parameters.
/// Keep small for Phase 1; expand later.
pub const ChatParams = struct {
    model: []const u8 = "mock",
    temperature: f32 = 0.7,
    top_p: f32 = 1.0,
    max_tokens: u32 = 256,
    stream: bool = false,
};

pub const LlmParams = struct {
    temperature: f32,
    max_tokens: u32,
};

pub const ProviderProfile = struct {
    id: i64 = 0,
    name: []const u8,
    ollama_url: []const u8,
    model: []const u8,
    created_at_ms: i64 = 0,
};

pub const PersonaProfile = struct {
    id: i64 = 0,
    name: []const u8,
    ai_name: []const u8,
    tone: []const u8,
    llm_chat: LlmParams,
    llm_reflection: LlmParams,
    llm_idle: LlmParams,
    llm_episode: LlmParams,
    conf_user_notes: f32,
    conf_episodes: f32,
    conf_idle: f32,
    conf_governor: f32,
    created_at_ms: i64 = 0,
};

test "Types basic sanity" {
    try std.testing.expectEqualStrings("user", roleToStr(.user));
    try std.testing.expectEqualStrings("note", kindToStr(.note));
}
