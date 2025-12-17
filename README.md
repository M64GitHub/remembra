<img src="docs/remembra.svg" width="60" alt="REMEMBRA"/>

# REMEMBRA

*A local chat workspace that remembers what matters.*

REMEMBRA is a local-first chat interface for Ollama.

At its core, it is a chat client with unlimited history, message bookmarks, and an editable message store.  
Optionally, it can be switched into **Reflection Mode**, where the AI is allowed to reflect, remember, and develop continuity over time.

You decide when REMEMBRA is just a conversation — and when it becomes reflective.

Chat (Reflection Enabled)
<img width="1920" height="1080" alt="Screenshot 2025-12-17 at 06 33 18" src="https://github.com/user-attachments/assets/a02e4a5c-8c24-440f-b966-2d036dfa0186" />

Standard Chat Mode
<img width="1920" height="1080" alt="Screenshot 2025-12-17 at 06 57 03" src="https://github.com/user-attachments/assets/f4c1eb9a-fbba-4c25-9bee-64d722cf14c0" />



View / Edit Stored Message
<img width="1920" height="1080" alt="Screenshot 2025-12-17 at 06 36 48" src="https://github.com/user-attachments/assets/f727ec12-b1b1-4058-90bb-16016a0fb206" />



## What Is This?

REMEMBRA is a chat client for local LLMs that runs entirely on your machine.
It is designed to be useful even without any AI memory features enabled.

When Reflection Mode is turned off, REMEMBRA behaves like a powerful, modern chat interface.
When Reflection Mode is enabled, an experimental memory system is activated that allows the AI to develop persistence across sessions.

## Who Is This For?

**If you just want a good chat client**
- You want a fast, local interface for Ollama
- You want unlimited scrollback, bookmarks, and saved message snippets
- You don’t want AI memory doing things behind your back

Use REMEMBRA with Reflection Mode off.

**If you want to keep and organize important conversations**
- You want to bookmark moments and extract ideas into a personal store
- You want editable, markdown-friendly clippings
- You want long conversations to stay navigable

REMEMBRA works as a personal chat workspace.

**If you’re curious about AI memory**
- You want to explore what happens when an AI can remember past sessions
- You care about governance, decay, and consent
- You want visibility into how memory decisions are made

Enable Reflection Mode and experiment.


## Features

### Chat Interface

- **Any Ollama model** - Connect to any model running on Ollama
- **Multiple personas** - Create personas with custom names, system prompts, and LLM parameters
- **Unlimited history** - Scroll through your complete conversation history; context markers show what the AI can currently "see"
- **Bookmarks** - Star messages for quick reference; jump back to them from the sidebar
- **Message store** - Save copies of messages to edit and reference later
- **Multi-select** - Select multiple messages and batch-copy them to the store
- **Markdown rendering** - Toggle markdown on/off per message
- **Event visibility** - Watch system decisions in real-time

### Reflection Mode (Experimental)

When enabled, REMEMBRA adds a memory layer around the LLM:

- **Persistent memory** - Structured memories with confidence scores that decay over time (7-day half-life)
- **Governed updates** - The AI proposes memories; an independent Governor decides what gets stored
- **Idle thinking** - During silence, the AI generates internal reflections
- **Episode compaction** - Long conversations are automatically summarized
- **Time awareness** - The system tracks gaps between sessions and acknowledges them naturally

The model generates text. The system maintains continuity.

## Quick Start

### Requirements

- **Zig 0.15.2+** - Build toolchain
- **Ollama** - Running on port 11434
- **Node.js** - For building the web interface

### Build and Run

```bash
zig build
./zig-out/bin/remembra server
open http://127.0.0.1:8080
```

On first run, REMEMBRA creates a SQLite database (`remembra.db`) with default schema and a starter persona.

## Architecture

REMEMBRA is a Zig HTTP server serving a Vue.js frontend, proxying LLM requests to Ollama. All data is stored in SQLite.

```
┌─────────────────────────────────────────────────────────┐
│                    Web Interface                         │
│  ┌──────────┐  ┌──────────────┐  ┌──────────────────┐   │
│  │ AI Mind  │  │    Chat      │  │  Context/Events  │   │
│  │ Memory   │  │              │  │                  │   │
│  │ Thoughts │  ├──────────────┤  │                  │   │
│  │ Profiles │  │ Saved Items  │  │                  │   │
│  ├──────────┤  │ Store        │  │                  │   │
│  │    or    │  │ Bookmarks    │  │                  │   │
│  └──────────┘  └──────────────┘  └──────────────────┘   │
└─────────────────────────────────────────────────────────┘
                          │
                    HTTP API
                          │
┌─────────────────────────────────────────────────────────┐
│                   Zig HTTP Server                        │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────────┐  │
│  │ Chat Engine │  │  Reflector  │  │  Idle Thinker   │  │
│  │             │  │  (optional) │  │   (optional)    │  │
│  └─────────────┘  └─────────────┘  └─────────────────┘  │
│                          │                               │
│                    ┌───────────┐                         │
│                    │ Governor  │                         │
│                    └───────────┘                         │
└─────────────────────────────────────────────────────────┘
                          │
              ┌───────────┴───────────┐
              │                       │
        ┌───────────┐           ┌───────────┐
        │  SQLite   │           │  Ollama   │
        │ Database  │           │   LLM     │
        └───────────┘           └───────────┘
```

REMEMBRA also exposes an Ollama-compatible endpoint. Any Ollama UI can connect to REMEMBRA instead of Ollama directly, gaining memory features transparently.

## The Memory System

When Reflection Mode is enabled, after each response the AI analyzes the conversation and proposes memories:

```
subject.predicate = object

Examples:
  user.prefers = "concise answers"
  user.working_on = "a Zig project"
  self.noticed = "user asks good follow-up questions"
```

Each memory has a confidence score (0.0-1.0) that decays over time. High-confidence memories persist; unused memories fade. The Governor filters proposals, enforcing rate limits, deduplication, and minimum confidence thresholds.

## Interface Overview

### Left Sidebar

Toggle between two modes using the icons at the top:

**AI Mind** (Remembra logo):
- Memory Inspector - View, search, delete stored memories
- Thoughts Viewer - See idle reflections
- Profiles - Manage personas and providers

**Saved Items** (Star):
- Store - Your saved message copies (editable, with markdown preview)
- Bookmarks - Quick links to starred messages

### Main Chat

- Continuous scrollable history
- Context indicators show which messages are in the LLM's window
- Selection circles for multi-select operations
- Star button to bookmark messages
- Markdown toggle per message

### Right Sidebar

- Context Viewer - See the exact prompt being sent
- Event Terminal - Real-time log of system decisions

## Development

```bash
# Build backend
zig build

# Build frontend
cd web && npm install && npm run build

# Run tests
zig build test

# Frontend dev server
cd web && npm run dev
```

## Configuration

Personas are configured through the web interface:

- Name and system prompt
- LLM parameters (temperature, max tokens) per operation
- Confidence thresholds for memory storage
- Provider selection

REMEMBRA includes 10 identity presets (Researcher, Companion, Coder, etc.) as starting points.

## Documentation

For detailed documentation, see the `docs/` directory:

- [Architecture](docs/remembra-architecture.svg) - System design
- [Flow](docs/remembra-flow.svg) - How a conversation turn works
- [Governor](docs/remembra-governor.svg) - Memory governance

## License

MIT
