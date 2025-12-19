//! Connection configuration for providers and storage.

pub const ConfigConnection = struct {
    ollama_url: []const u8 = "http://127.0.0.1:11434",
    ollama_model: []const u8 = "gpt-oss",

    database_path: [:0]const u8 = "remembra.db",
    event_port: u16 = 8081,
};
