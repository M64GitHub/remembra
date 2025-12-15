//! Identity configuration for persona and LLM parameters.

const MemoryPolicy = @import("MemoryPolicy.zig").MemoryPolicy;

pub const LlmParams = struct {
    temperature: f32,
    max_tokens: u32,
};

pub const ConfigIdentity = struct {
    name: []const u8 = "REMEMBRA",

    default_tone: []const u8 = "helpful, concise, grounded, engaging",
    default_memory_contract: []const u8 =
        "Memory is read-only unless the user explicitly asks " ++
        "to store/update something.",

    llm_chat: LlmParams = .{ .temperature = 0.7, .max_tokens = 256 },
    llm_reflection: LlmParams = .{ .temperature = 0.2, .max_tokens = 512 },
    llm_idle: LlmParams = .{ .temperature = 0.4, .max_tokens = 160 },
    llm_episode: LlmParams = .{ .temperature = 0.2, .max_tokens = 512 },

    confidence_user_notes: f32 = 0.7,
    confidence_episodes: f32 = 0.85,
    confidence_idle_thoughts: f32 = 0.55,
    confidence_min_governor: f32 = 0.6,

    reentry_threshold_ms: i64 = 6 * 60 * 60 * 1000,

    memory_policy: MemoryPolicy = .{},
};
