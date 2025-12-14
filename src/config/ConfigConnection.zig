//! Connection configuration for providers and storage.

pub const ConfigConnection = struct {
    use_sqlite: bool = true,
    use_ollama: bool = true,

    ollama_url: []const u8 = "http://127.0.0.1:11434",
    ollama_model: []const u8 = "llama3.2",

    database_path: [:0]const u8 = "remembra.db",
};
