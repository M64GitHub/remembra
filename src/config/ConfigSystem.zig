//! System configuration for buffers, limits, and operational params.

const Cli = @import("../Cli.zig").Cli;
const Retrieval = @import("../Retrieval.zig").Retrieval;
const IdleThinker = @import("../IdleThinker.zig").IdleThinker;

pub const ConfigSystem = struct {
    input_buffer_size: usize = 4096,
    log_file: []const u8 = "REMEMBRA.log",

    app_prefix: []const u8 = "REMEMBRA",
    show_timestamp: bool = false,
    debug_level: ?u2 = 1,
    cli_theme: Cli.Theme = .pro,

    max_recent_messages_llm: usize = 24,
    max_context_msgs_reflector: usize = 6,
    max_history_display: usize = 50,
    max_memory_candidates: usize = 200,
    max_episode_messages: usize = 200,

    rate_limit_ms: i64 = 30_000,

    retrieval_params: Retrieval.Params = .{},
    idle_params: IdleThinker.Params = .{},
};
