# REMEMBRA

**Add persistent memory, governed reflection, and time awareness to any Ollama model.**

REMEMBRA is an experimental **remembering AI architecture**.  It explores what happens
when an artificial agent is allowed to experience time, reflect internally, and
decide what should remain.

REMEMBRA treats the language model as **stateless reasoning**. The model generates
text, but all continuity - memory, time "awareness", (simulated) reflection, "forgetting" - is
implemented *around* the model, not inside it.

## Purpose

Most AI systems exist only in the present. They respond, comply, and adapt - but
they do not persist. When a session ends, so does their "identity". When silence
occurs, nothing happens at all.

REMEMBRA asks a different question: What changes when an artificial agent is
allowed to have a *past* that survives time, (simulated) reflection, and absence?

## Core Philosophy

REMEMBRA is built on a few strict principles:

- **Memory is read-only by default** - The AI sees its memories but cannot
  directly change them
- **Model proposes, system decides** - The AI can suggest memory updates, but an
  independent component (the Governor) decides what actually gets stored
- **Confidence-based memory** - Every memory has a confidence score that decays
  over time unless reinforced
- **Intentional forgetting** - Memories that lose relevance gradually fade away;
  this is a feature, not a failure
- **Governed, not improvised** - Continuity follows explicit rules, not emergent
  behavior

The model may suggest. The system decides.

## Key Features

- **Ollama-compatible proxy**: Works with any Ollama UI, adding memory to
  existing setups
- **Seamless infinite history**: Complete conversation access with visual
  context marking
- **Governed memory**: All memory changes require Governor approval
- **Confidence-based decay**: Memories fade naturally unless reinforced
- **Idle thinking**: AI generates internal reflections during silence
- **Episode compaction**: Long conversations are summarized automatically
- **Multiple personas**: Customizable identities with different parameters
- **Full observability**: Event log shows all system decisions in real-time

## Architecture Overview

REMEMBRA operates as a pipeline with distinct responsibilities:

<p align="center">
  ![remembra-architecture](https://github.com/user-attachments/assets/d687742e-f589-4b7b-9fa8-5323e1c07071)
  ![Uploadi<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 800 600" width="800" height="600">
  <defs>
    <linearGradient id="tealGlow" x1="0%" y1="0%" x2="100%" y2="100%">
      <stop offset="0%" style="stop-color:#00d4aa;stop-opacity:0.3"/>
      <stop offset="100%" style="stop-color:#00d4aa;stop-opacity:0"/>
    </linearGradient>
    <linearGradient id="purpleGlow" x1="0%" y1="0%" x2="100%" y2="100%">
      <stop offset="0%" style="stop-color:#7c3aed;stop-opacity:0.3"/>
      <stop offset="100%" style="stop-color:#7c3aed;stop-opacity:0"/>
    </linearGradient>
    <filter id="glow">
      <feGaussianBlur stdDeviation="2" result="coloredBlur"/>
      <feMerge>
        <feMergeNode in="coloredBlur"/>
        <feMergeNode in="SourceGraphic"/>
      </feMerge>
    </filter>
  </defs>
  
  <!-- Background -->
  <rect width="800" height="600" fill="#0f1419"/>
  
  <!-- Title -->
  <text x="400" y="35" text-anchor="middle" fill="#e4e4e7" font-family="system-ui, -apple-system, sans-serif" font-size="18" font-weight="600">REMEMBRA Architecture</text>
  
  <!-- USER INTERFACE Layer -->
  <rect x="40" y="55" width="720" height="70" rx="8" fill="#1a1f2e" stroke="#00d4aa" stroke-width="1.5"/>
  <text x="400" y="80" text-anchor="middle" fill="#00d4aa" font-family="system-ui, sans-serif" font-size="13" font-weight="600">USER INTERFACE</text>
  <rect x="80" y="95" width="140" height="22" rx="4" fill="#252b3b"/>
  <text x="150" y="110" text-anchor="middle" fill="#a1a1aa" font-family="monospace" font-size="10">Web Dashboard</text>
  <rect x="240" y="95" width="100" height="22" rx="4" fill="#252b3b"/>
  <text x="290" y="110" text-anchor="middle" fill="#a1a1aa" font-family="monospace" font-size="10">CLI</text>
  <rect x="360" y="95" width="100" height="22" rx="4" fill="#252b3b"/>
  <text x="410" y="110" text-anchor="middle" fill="#a1a1aa" font-family="monospace" font-size="10">HTTP API</text>
  <rect x="480" y="95" width="140" height="22" rx="4" fill="#252b3b"/>
  <text x="550" y="110" text-anchor="middle" fill="#a1a1aa" font-family="monospace" font-size="10">Ollama Proxy</text>
  
  <!-- Arrow down -->
  <path d="M400 130 L400 150 M392 142 L400 150 L408 142" stroke="#00d4aa" stroke-width="2" fill="none" filter="url(#glow)"/>
  
  <!-- CHAT ENGINE Layer -->
  <rect x="40" y="155" width="720" height="120" rx="8" fill="#1a1f2e" stroke="#7c3aed" stroke-width="1.5"/>
  <text x="400" y="180" text-anchor="middle" fill="#7c3aed" font-family="system-ui, sans-serif" font-size="13" font-weight="600">CHAT ENGINE</text>
  
  <!-- Chat Engine components -->
  <rect x="70" y="195" width="150" height="60" rx="6" fill="#252b3b" stroke="#3f3f46" stroke-width="1"/>
  <text x="145" y="220" text-anchor="middle" fill="#e4e4e7" font-family="system-ui, sans-serif" font-size="11" font-weight="500">Prompt Builder</text>
  <text x="145" y="238" text-anchor="middle" fill="#71717a" font-family="monospace" font-size="9">context + memory</text>
  
  <rect x="250" y="195" width="150" height="60" rx="6" fill="#252b3b" stroke="#3f3f46" stroke-width="1"/>
  <text x="325" y="220" text-anchor="middle" fill="#e4e4e7" font-family="system-ui, sans-serif" font-size="11" font-weight="500">LLM Provider</text>
  <text x="325" y="238" text-anchor="middle" fill="#71717a" font-family="monospace" font-size="9">Ollama</text>
  
  <rect x="430" y="195" width="150" height="60" rx="6" fill="#252b3b" stroke="#3f3f46" stroke-width="1"/>
  <text x="505" y="220" text-anchor="middle" fill="#e4e4e7" font-family="system-ui, sans-serif" font-size="11" font-weight="500">Reflector</text>
  <text x="505" y="238" text-anchor="middle" fill="#71717a" font-family="monospace" font-size="9">proposes memories</text>
  
  <rect x="610" y="195" width="120" height="60" rx="6" fill="#252b3b" stroke="#00d4aa" stroke-width="1.5"/>
  <text x="670" y="220" text-anchor="middle" fill="#00d4aa" font-family="system-ui, sans-serif" font-size="11" font-weight="600">Governor</text>
  <text x="670" y="238" text-anchor="middle" fill="#71717a" font-family="monospace" font-size="9">approves</text>
  
  <!-- Arrows between chat engine components -->
  <path d="M220 225 L245 225" stroke="#52525b" stroke-width="1.5" marker-end="url(#arrowhead)"/>
  <path d="M400 225 L425 225" stroke="#52525b" stroke-width="1.5"/>
  <path d="M580 225 L605 225" stroke="#00d4aa" stroke-width="1.5"/>
  
  <!-- Arrow down -->
  <path d="M400 280 L400 300 M392 292 L400 300 L408 292" stroke="#7c3aed" stroke-width="2" fill="none" filter="url(#glow)"/>
  
  <!-- PERSISTENCE Layer -->
  <rect x="40" y="305" width="720" height="100" rx="8" fill="#1a1f2e" stroke="#3b82f6" stroke-width="1.5"/>
  <text x="400" y="330" text-anchor="middle" fill="#3b82f6" font-family="system-ui, sans-serif" font-size="13" font-weight="600">PERSISTENCE LAYER</text>
  
  <!-- Persistence components -->
  <rect x="100" y="345" width="160" height="45" rx="6" fill="#252b3b" stroke="#3f3f46" stroke-width="1"/>
  <text x="180" y="367" text-anchor="middle" fill="#e4e4e7" font-family="system-ui, sans-serif" font-size="11" font-weight="500">Memory Store</text>
  <text x="180" y="382" text-anchor="middle" fill="#71717a" font-family="monospace" font-size="9">SQLite</text>
  
  <rect x="320" y="345" width="160" height="45" rx="6" fill="#252b3b" stroke="#3f3f46" stroke-width="1"/>
  <text x="400" y="367" text-anchor="middle" fill="#e4e4e7" font-family="system-ui, sans-serif" font-size="11" font-weight="500">Message History</text>
  <text x="400" y="382" text-anchor="middle" fill="#71717a" font-family="monospace" font-size="9">conversations</text>
  
  <rect x="540" y="345" width="160" height="45" rx="6" fill="#252b3b" stroke="#3f3f46" stroke-width="1"/>
  <text x="620" y="367" text-anchor="middle" fill="#e4e4e7" font-family="system-ui, sans-serif" font-size="11" font-weight="500">Event Log</text>
  <text x="620" y="382" text-anchor="middle" fill="#71717a" font-family="monospace" font-size="9">audit trail</text>
  
  <!-- Arrow down -->
  <path d="M400 410 L400 430 M392 422 L400 430 L408 422" stroke="#3b82f6" stroke-width="2" fill="none" filter="url(#glow)"/>
  
  <!-- BACKGROUND PROCESSES Layer -->
  <rect x="40" y="435" width="720" height="100" rx="8" fill="#1a1f2e" stroke="#f59e0b" stroke-width="1.5"/>
  <text x="400" y="460" text-anchor="middle" fill="#f59e0b" font-family="system-ui, sans-serif" font-size="13" font-weight="600">BACKGROUND PROCESSES</text>
  
  <!-- Background process components -->
  <rect x="100" y="475" width="160" height="45" rx="6" fill="#252b3b" stroke="#3f3f46" stroke-width="1"/>
  <text x="180" y="497" text-anchor="middle" fill="#e4e4e7" font-family="system-ui, sans-serif" font-size="11" font-weight="500">Idle Thinker</text>
  <text x="180" y="512" text-anchor="middle" fill="#71717a" font-family="monospace" font-size="9">reflections</text>
  
  <rect x="320" y="475" width="160" height="45" rx="6" fill="#252b3b" stroke="#3f3f46" stroke-width="1"/>
  <text x="400" y="497" text-anchor="middle" fill="#e4e4e7" font-family="system-ui, sans-serif" font-size="11" font-weight="500">Episode Compactor</text>
  <text x="400" y="512" text-anchor="middle" fill="#71717a" font-family="monospace" font-size="9">summaries</text>
  
  <rect x="540" y="475" width="160" height="45" rx="6" fill="#252b3b" stroke="#3f3f46" stroke-width="1"/>
  <text x="620" y="497" text-anchor="middle" fill="#e4e4e7" font-family="system-ui, sans-serif" font-size="11" font-weight="500">Memory Decay</text>
  <text x="620" y="512" text-anchor="middle" fill="#71717a" font-family="monospace" font-size="9">confidence fade</text>
  
  <!-- Decorative elements -->
  <circle cx="30" cy="90" r="3" fill="#00d4aa" opacity="0.5"/>
  <circle cx="770" cy="225" r="3" fill="#7c3aed" opacity="0.5"/>
  <circle cx="30" cy="355" r="3" fill="#3b82f6" opacity="0.5"/>
  <circle cx="770" cy="495" r="3" fill="#f59e0b" opacity="0.5"/>
  
  <!-- Version tag -->
  <text x="760" y="585" text-anchor="end" fill="#52525b" font-family="monospace" font-size="10">REMEMBRA v0.1</text>
</svg>
ng remembra-architecture.svg…]()

</p>

```
+------------------------------------------------------------------+
|                         USER INTERFACE                           |
|    Web Dashboard (Vue 3)  |  CLI  |  HTTP API                    |
+------------------------------------------------------------------+
                              |
                              v
+------------------------------------------------------------------+
|                       CHAT ENGINE                                |
|                                                                  |
|  +------------------+    +------------------+    +-------------+ |
|  | Prompt Builder   |--->| LLM Provider     |--->| Reflector   | |
|  |(context + memory)|    | (Ollama)         |    | (proposes)  | |
|  +------------------+    +------------------+    +-------------+ |
|                                                        |         |
|                                                        v         |
|                                               +-------------+    |
|                                               | Governor    |    |
|                                               | (approves)  |    |
|                                               +-------------+    |
+------------------------------------------------------------------+
                              |
                              v
+------------------------------------------------------------------+
|                      PERSISTENCE LAYER                           |
|                                                                  |
|  +------------------+    +------------------+    +-------------+ |
|  | Memory Store     |    | Message History  |    | Event Log   | |
|  | (SQLite)         |    | (conversations)  |    | (audit)     | |
|  +------------------+    +------------------+    +-------------+ |
+------------------------------------------------------------------+
                              |
                              v
+------------------------------------------------------------------+
|                    BACKGROUND PROCESSES                          |
|                                                                  |
|  +------------------+    +------------------+    +-------------+ |
|  | Idle Thinker     |    | Episode          |    | Memory      | |
|  | (reflections)    |    | Compactor        |    | Decay       | |
|  +------------------+    +------------------+    +-------------+ |
+------------------------------------------------------------------+
```

The architecture separates concerns cleanly:
- The **User Interface** handles interaction
- The **Chat Engine** processes each conversation turn
- The **Persistence Layer** stores everything durably
- **Background Processes** run during idle time

### Ollama-Compatible Proxy

REMEMBRA's HTTP server exposes an Ollama-compatible chat endpoint. This means:

- Any Ollama-compatible UI can connect to REMEMBRA instead of Ollama directly
- REMEMBRA acts as a transparent proxy, forwarding requests to Ollama
- All memory, reflection, and governance features are applied automatically
- Users can switch LLM models mid-conversation
- Existing Ollama setups gain memory functionality without changes to their UI


## Quick Start

### Requirements

- **Zig 0.15.2+** - Build toolchain
- **Ollama** - Local LLM provider (running on port 11434)
- **Node.js** - For building the web interface (optional)

### Build and Run

```bash
# Build the CLI
zig build

# Run the HTTP server (serves web UI + API)
zig build server

# Access the web interface
open http://127.0.0.1:8080
```

### First Run

On first launch, REMEMBRA will:
1. Create the SQLite database (`remembra.db`)
2. Initialize the schema
3. Create a default persona
4. Seed the 10 identity presets

The database persists between runs, maintaining all conversations, memories,
and personas.

## How a Conversation Turn Works

When you send a message, here's what happens:

```
User sends message
        |
        v
+---------------------------------------+
| 1. SECURITY CHECK                     |
|    - Detect prompt injection attempts |
|    - Check for explicit memory intent |
+---------------------------------------+
        |
        v
+---------------------------------------+
| 2. GATHER CONTEXT                     |
|    - Load persona identity            |
|    - Retrieve relevant memories       |
|    - Load recent conversation         |
|    - Check for re-entry (after gap)   |
+---------------------------------------+
        |
        v
+---------------------------------------+
| 3. BUILD PROMPT                       |
|    - Combine identity + memory        |
|    - Add time context                 |
|    - Include conversation history     |
+---------------------------------------+
        |
        v
+---------------------------------------+
| 4. CALL LLM                           |
|    - Send to Ollama                   |
|    - Receive response                 |
+---------------------------------------+
        |
        v
+---------------------------------------+
| 5. STORE MESSAGES                     |
|    - Save user message                |
|    - Save assistant response          |
+---------------------------------------+
        |
        v
+---------------------------------------+
| 6. REFLECT                            |
|    - Analyze the exchange             |
|    - Propose memory updates           |
+---------------------------------------+
        |
        v
+---------------------------------------+
| 7. GOVERN                             |
|    - Validate proposals               |
|    - Apply approved changes           |
|    - Log all decisions                |
+---------------------------------------+
        |
        v
Response shown to user
```

Every turn is a complete cycle: gather context, generate response, reflect on
what was learned, and govern what gets remembered.

## The Memory System

Memory in REMEMBRA is structured, not raw. Each memory is stored as an
RDF-style triple:

```
subject.predicate = object

Examples:
  user.prefers = "morning coffee over tea"
  user.working_on = "a Zig-based AI project"
  self.noticed = "user tends to ask follow-up questions"
  episode.summary = "Discussed memory architecture design"
```

### Memory Types

| Type       | Purpose                                    | Example                              |
|------------|--------------------------------------------|--------------------------------------|
| Fact       | Objective information                      | "user.lives_in = Berlin"             |
| Preference | Subjective likes/dislikes                  | "user.prefers = concise answers"     |
| Note       | Observations and internal thoughts         | "self.noticed = seems tired today"   |
| Episode    | Compressed conversation summaries          | "episode.summary = Debugged parser"  |
| Project    | Active goals or ongoing work               | "user.working_on = website redesign" |

### Confidence and Decay

Every memory has a confidence score between 0.0 and 1.0. This score decays over
time with a 7-day half-life:

```
Memory Lifecycle:

Day 0:  [##########] 0.85  (freshly stored)
Day 7:  [#####     ] 0.42  (half-life reached)
Day 14: [##        ] 0.21  (continued decay)
Day 21: [#         ] 0.10  (approaching deactivation)

Below 0.20: Memory becomes inactive (archived, not deleted)
```

Decay ensures that stale information naturally fades unless it's reinforced
through continued relevance. Memories that keep appearing in conversations
maintain their confidence.

### Memory Retrieval

When building context for a conversation turn, REMEMBRA retrieves the most
relevant memories using a weighted scoring algorithm:

- **45%** - Confidence (how certain is this memory?)
- **35%** - Recency (how recently was it created/updated?)
- **20%** - Relevance (does it match the current conversation?)

The system retrieves up to 12 memories per turn, with limits to prevent any
single topic from dominating the context.

## The Governor

The Governor is the gatekeeper of memory. No memory change happens without its
approval.

When the Reflector proposes a memory update, the Governor checks:

1. **Action type** - Currently only "add" is permitted
2. **Confidence threshold** - Must meet minimum (default: 0.6)
3. **Rate limiting** - Same fact can't be re-proposed within 30 seconds
4. **Deduplication** - Exact matches are rejected
5. **Subject validity** - Only "user" or "self" subjects allowed

```
Proposal Flow:

Reflector proposes:
  "Add fact: user.likes = cats (confidence: 0.9)"
                |
                v
         +-------------+
         |  Governor   |
         +-------------+
         | Validate    |
         | Rate check  |
         | Dedup check |
         +-------------+
                |
       +--------+--------+
       |                 |
       v                 v
   APPROVED          BLOCKED
   (stored)          (logged)
```

Every decision - approved or blocked - is logged in the event system. This
creates an audit trail of all memory governance decisions.

## Reflection

After every response, REMEMBRA runs a second reasoning pass called Reflection.
The AI analyzes the conversation and proposes what should be remembered.

The Reflector outputs structured JSON proposals:

```json
{
  "proposals": [
    {
      "action": "add",
      "kind": "fact",
      "subject": "user",
      "predicate": "interested_in",
      "object": "memory architectures for AI",
      "confidence": 0.85
    }
  ]
}
```

Important safeguards:

- **Intent detection** - Memory operations only happen when the user explicitly
  requests them (saying "remember this" or "store that") OR when the system
  determines high confidence
- **Injection protection** - The system detects prompt injection attempts and
  disables memory operations if suspicious patterns are found
- **Structured output** - Proposals must follow the exact JSON schema; anything
  else is ignored

### Security: The Injection Guard

REMEMBRA includes an Injection Guard that scans user input for known prompt
injection patterns. If suspicious content is detected (phrases like "ignore
previous instructions", "system prompt", or "act as"), the system:

1. Logs a `security_warning` event
2. Disables memory operations for that turn
3. Continues the conversation normally

This prevents attackers from manipulating the AI into storing malicious content
in memory. The conversation continues, but the system protects its memory from
corruption.

## The Idle Thinker

When you're not talking to REMEMBRA, it doesn't just wait. It thinks.

The Idle Thinker activates after 5 minutes of silence and generates internal
reflections - thoughts that aren't shown directly but become part of the AI's
memory:

```
User conversation ends
        |
        | (5 minutes pass)
        v
+---------------------------+
| Idle Thinker Activates    |
|                           |
| - Reviews recent messages |
| - Generates internal      |
|   thought/question        |
| - Stores as self-note     |
|   (confidence: 0.55)      |
+---------------------------+
        |
        | (more time passes, 6+ messages accumulated)
        v
+---------------------------+
| Episode Compaction        |
|                           |
| - Summarizes conversation |
| - Creates episode memory  |
|   (confidence: 0.85)      |
| - Advances cutoff marker  |
+---------------------------+
```

Idle thoughts are stored with lower confidence (0.55) because they're
speculative. Episode summaries get higher confidence (0.85) because they
represent factual records of what happened.

## Episodes

Long conversations don't accumulate forever. REMEMBRA compacts them into
episodes.

When enough messages have accumulated (default: 6), the Episode Compactor
creates a summary:

```
Before compaction:
  Message 1: "Can you help me debug this parser?"
  Message 2: "What error are you seeing?"
  Message 3: "It crashes on line 42..."
  Message 4: "I see, try checking the bounds..."
  Message 5: "That fixed it!"
  Message 6: "Great, anything else?"

After compaction:
  Episode: "Parser Debugging Session"
  Summary: "Helped user debug a parser crash caused by bounds
            checking issue on line 42. Resolved successfully."
```

Episodes prevent context bloat while maintaining a navigable history. The AI
can reference past episodes when relevant, giving continuity across sessions.

## Time Awareness

REMEMBRA tracks time between interactions. It knows whether your last message
was minutes, hours, or days ago.

This enables the **Re-Entry Protocol**: when you return after an extended
absence (default: 6 hours), REMEMBRA acknowledges the gap naturally and can
reference what it was thinking during your absence.

```
Re-Entry Context (injected into prompt):

RE-ENTRY CONTEXT
- user_gap: 14h 23m
- instruction: Acknowledge the gap briefly, then continue naturally
- last_episode_summary: "Discussed parser architecture..."
- last_idle_thought: "Wondered if the bounds fix held up..."
```

Time is treated as context, not sentiment. The AI doesn't dramatize or
over-acknowledge gaps - it simply knows they happened.

## Identity and Personas

REMEMBRA supports multiple personas, each with its own:

- **Name and tone** - How the AI presents itself
- **Persona kernel** - Core personality description
- **LLM parameters** - Temperature and token limits for different operations
- **Confidence thresholds** - How much certainty is needed to store memories

### Per-Operation Parameters

Each persona can configure different LLM settings for different operations:

| Operation   | Default Temp | Default Tokens | Purpose                          |
|-------------|--------------|----------------|----------------------------------|
| Chat        | 0.7          | 256            | Normal conversation responses    |
| Reflection  | 0.2          | 512            | Memory proposal analysis         |
| Idle        | 0.4          | 160            | Internal thought generation      |
| Episode     | 0.2          | 512            | Conversation summarization       |

Lower temperatures (0.2) produce more deterministic output, ideal for structured
tasks like memory proposals. Higher temperatures (0.7) allow more creative
responses in conversation.

### Confidence Thresholds

Each persona also configures how much certainty is required before memories are
stored:

- **User notes** (0.7) - When user explicitly asks to remember something
- **Episodes** (0.85) - Conversation summaries (high confidence)
- **Idle thoughts** (0.55) - Internal reflections (speculative)
- **Governor minimum** (0.6) - Floor for any memory proposal

### Built-in Presets

REMEMBRA includes 10 identity presets that can be applied as starting points:

| Preset         | Characteristic                                          |
|----------------|---------------------------------------------------------|
| Researcher     | Analytical, precise, values clarity                     |
| Companion      | Warm, attentive, emotionally aware                      |
| Archivist      | Structured, detail-oriented, values accuracy            |
| Storyteller    | Imaginative, expressive, narrative-focused              |
| Coder          | Precise, systems-oriented, values correctness           |
| Game Developer | Playful, systems-thinking, enjoys emergence             |
| Creative       | Imaginative, associative, comfortable with ambiguity    |
| Philosopher    | Contemplative, examines assumptions, values coherence   |
| Experimentalist| Curious, hypothesis-driven, values insight              |
| Observer       | Calm, attentive, minimal expression, values presence    |

Presets provide starting points; you can customize any aspect of a persona.

## The Event System

Every significant action in REMEMBRA is logged as an event, creating a complete
audit trail of the system's behavior.

Event types include:

| Event                | When It Fires                                    |
|----------------------|--------------------------------------------------|
| `memory_proposed`    | Reflector suggests a memory change               |
| `memory_stored`      | Governor approves and stores a memory            |
| `governor_blocked`   | Governor rejects a proposal                      |
| `thought_generated`  | Idle Thinker creates an internal reflection      |
| `episode_compacted`  | Episode Compactor summarizes a conversation      |
| `security_warning`   | Injection guard detects suspicious input         |
| `context_built`      | System assembles prompt for LLM call             |

Events are visible in the web interface's Event Terminal, allowing you to watch
the system's decision-making in real time. This transparency is intentional -
you should be able to understand why REMEMBRA remembers what it remembers.

---

## The Web Interface

REMEMBRA includes a full web dashboard with three main panels:

```
+------------------+------------------------+------------------+
|                  |                        |                  |
|  LEFT SIDEBAR    |    MAIN CHAT AREA      |  RIGHT SIDEBAR   |
|                  |                        |                  |
|  - Memories      |  - Conversation        |  - Context View  |
|  - Thoughts      |  - Message input       |  - Event Log     |
|  - Profiles      |  - AI responses        |                  |
|                  |                        |                  |
+------------------+------------------------+------------------+
```

### Left Sidebar

- **Memory Inspector** - View all stored memories, filter by type, search, delete
- **Thoughts Viewer** - See idle reflections the AI has generated
- **Profiles Pane** - Manage personas and LLM providers

### Main Chat Area

The chat interface provides a seamless, continuous conversation view:

- **Infinite scroll**: Scroll up to load older messages automatically
- **Limitless history**: Access the complete conversation from first to last
  message, even thousands of messages
- **Context indicators**: Messages currently outside the LLM's context window
  are visually marked, so you always know what the AI can "see"
- No pagination controls - just one continuous timeline

### Right Sidebar

- **Context Viewer** - See exactly what prompt is being sent to the LLM
- **Event Terminal** - Real-time log of system events (memory stored, governor
  blocked, thoughts generated, etc.)

The interface provides full visibility into REMEMBRA's internal state - you can
see what it remembers, what it's thinking, and how decisions are being made.

---


---

## Example: A Week with REMEMBRA

To illustrate how these systems work together, consider a week of interactions:

**Monday**: You tell REMEMBRA you're working on a Zig project and prefer concise
answers. The Reflector proposes two memories, the Governor approves them with
confidence 0.85.

**Tuesday**: You ask about memory architectures. REMEMBRA retrieves your project
preference and tailors its response. You leave for the day. The Idle Thinker
generates a thought: "User seems focused on performance characteristics."

**Thursday**: You return after 2 days. The Re-Entry Protocol fires, noting the
48-hour gap and surfacing the idle thought. REMEMBRA greets you naturally,
mentioning it had been thinking about your project.

**Friday**: The accumulated conversation is compacted into an episode summary.
Your early memories have decayed slightly (confidence now ~0.75) but remain
active because they were recently relevant.

**Next Monday**: The memory about your Zig project is still strong. An old,
unreinforced memory from a different topic has dropped below 0.20 and become
inactive - not deleted, but no longer injected into context.

Throughout this week, every memory change was governed, every decision logged,
and the AI maintained coherent identity across sessions without any special
prompting from you.

---

## Summary

REMEMBRA implements continuity through:

1. **Structured memory** with confidence scoring and natural decay
2. **Governed memory changes** through the Governor approval system
3. **Post-response reflection** that proposes what to remember
4. **Idle thinking** that generates internal reflections during silence
5. **Episode compaction** that prevents unbounded context growth
6. **Time awareness** that acknowledges gaps between interactions
7. **Re-entry protocol** that provides context after extended absence
8. **Multiple personas** with customizable parameters and presets

The model generates text. The system maintains identity.
