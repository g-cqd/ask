# Research Study: Context Optimization, Interactive Ergonomics, and Built-in Tool Consolidation

Date: 2026-10-27  
Status: Complete study and architectural specification

---

## 1. Executive Summary & Problem Statements

This study consolidates investigations into five interrelated areas of `ask`:
1. **Context Consumption at Session Start**: Skills catalog advertisement and MCP server tool definitions consume disproportionate prompt context before the user even issues a prompt.
2. **Built-in Tool Architecture & Consolidation**:
   - Merging `write` and `edit` into a single, unified file modification tool.
   - Deconstructing `job_input` and `job_stop`, clarifying their differences, and consolidating them into a unified process lifecycle tool.
   - Absorbing `wait` from an explicit standalone tool into a transitive parameter for long-running / asynchronous tools (`bash`/`shell`, `job`).
3. **Shell / Bash Tooling and Visual Representation**:
   - Exposing the user's `$SHELL` dynamically.
   - Renaming presentation blocks from `bash` to `shell`.
   - Re-architecting first-line tool block formatting (`tool · target · parameters · status`).
   - Unfolded display of full multi-line commands with intelligent heredoc (`cat << 'EOF'`) folding.
4. **Interactive TUI Input & Slash Commands**:
   - Word jumping with Alt/Option + Left/Right arrows in `PromptEditor`.
   - Immediate entry into interactive choice lists for `/` commands (`/model`, `/thinking`, `/resume`) upon pressing Enter.
   - Categorized and structured `/` command picker.
   - Clean replacement of queued steering prompt notifications when accepted into the conversation.
5. **Interactive Configuration Editor & Session Exit Resume Notice**:
   - Interactive directional arrow navigation through JSON/JSON5 configuration options (`config.json`).
   - Printing exact copy-paste `ask --resume <id> <flags>` commands on session teardown.

---

## 2. Built-in Tool Surface Rework & Consolidation

### 2.1 Write and Edit: Merging into a Unified File Tool (`write` / `file_write`)
Currently:
- `write` takes `path` and `content`. It unconditionally overwrites or creates a file.
- `edit` takes `path`, `old_text`, `new_text`, and optional `replace_all`. It reads the file, verifies unique byte occurrence of `old_text`, and substitutes `new_text`.
- Both independently inject `SandboxRequest.property` into their schema schemas, duplicating schema token overhead.

#### Can and Should They Be Merged?
**Yes.** Consolidating into a single tool (`write` or `file_edit` / `file_write`) is highly advantageous:
- **Token Efficiency**: Eliminates an entire `ToolDefinition` from `ModelRequest.tools`, saving ~250–350 tokens per request.
- **Unified Semantics**:
  ```swift
  struct Arguments: Decodable {
      let path: String
      let content: String?        // If provided without old_text -> full file creation/replacement
      let oldText: String?        // If provided with new_text -> exact string substitution
      let newText: String?
      let replaceAll: Bool?
      let sandbox: SandboxRequest?
  }
  ```
- **Operational Rules**:
  - If `old_text` is supplied without `new_text`, fail with `"new_text required for targeted replacement"`.
  - If `old_text` is present: perform targeted byte search/replace (the `edit` contract).
  - If only `content` (or `new_text` without `old_text`) is present: write whole file (the `write` contract).
  - Both operations share the same authorized file access check (`FileTools.authorized`).

---

### 2.2 Difference Between `job_input` and `job_stop`, and How to Improve Them

#### Current Differences:
1. **`job_input`**:
   - Targets a running background job (`job` ID string).
   - Writes arbitrary bytes to standard input via `job.write(Array(text.utf8))`.
   - Optionally sends EOF (`close_input == true`).
   - Waits a short `yield_seconds` (default 1s, max 60s) for subsequent output.
   - Returns unread output lines and flags whether the process is still running or ended.
2. **`job_stop`**:
   - Targets a running job.
   - Initiates graceful teardown: SIGTERM to the process group, 2-second grace period, then SIGKILL.
   - Waits for process termination (`await job.ended()`).
   - Returns final captured output and status `[job stopped]`.

#### How to Improve & Consolidate:
Instead of maintaining two discrete tools plus `wait`, consolidate into a single **`job`** management tool:
```json
{
  "name": "job",
  "description": "Interact with a background job: send input, close standard input, check status, or stop it.",
  "properties": {
    "job": { "type": "string", "description": "The job ID (e.g. job_1)" },
    "action": { "type": "string", "enum": ["input", "status", "stop"], "default": "input" },
    "text": { "type": "string", "description": "Text to write to standard input (action=input)" },
    "close_input": { "type": "boolean", "description": "Close standard input after writing EOF" },
    "timeout_seconds": { "type": "integer", "description": "Seconds to wait for output (default 1, max 600)" }
  }
}
```
This reduces tool schema bloat by 2 tools (~500 tokens) while preserving exact process semantics.

---

### 2.3 The `wait` Tool: Standalone vs. Transitive Passthrough

#### The Thesis:
Currently, `wait` can wait on four distinct triggers:
1. A background job ending (`job`).
2. A background job output containing text (`output_contains`).
3. A local port opening (`port_open`).
4. A file appearing on disk (`file_exists`).

In practice:
- 90% of `wait` usages by models are immediately preceded by running a command in background via `bash(yield_seconds: ...)`.
- Model architectures struggle to coordinate `yield_seconds` followed by a second turn calling `wait`.

#### Recommendation:
1. **Transitive Passthrough to Shell / Bash**:
   Add wait parameters directly into `shell`:
   ```swift
   ToolProperty.string("wait_for_output").optional
   ToolProperty.integer("wait_for_port").optional
   ToolProperty.string("wait_for_file").optional
   ```
   If specified, `shell` launches the process, starts the listener/watchdog, and suspends return until the condition is met (or `timeout_seconds` elapses).
2. **Retaining Minimal `wait` or Folding into `job`**:
   If an asynchronous job is already running from a prior turn, `job(action: "wait", ...)` handles job completion or output matching. Standalone file/port polling can either remain as lightweight parameters in `job` or stay as an internal kernel mechanism rather than a first-class LLM tool.

---

## 3. Shell / Bash Tooling and Visual Presentation

### 3.1 Exposing the User's `$SHELL`
- In macOS and modern Unix environments, `/bin/bash` is bash 3.2 (legacy) or a compatibility wrapper. Most developers use `/bin/zsh`, `/opt/homebrew/bin/bash`, or `fish`.
- **Implementation**:
  - `JobProcess.swift`: Read `ProcessInfo.processInfo.environment["SHELL"]`. Validate the binary exists and is executable.
  - Expose `shell` parameter in tool arguments:
    ```swift
    ToolProperty.string("shell", description: "Shell binary to use (default: user's shell: /bin/zsh)").optional
    ```
  - Display the active shell in the system prompt context or tool parameter default so the model knows syntax constraints (e.g. zsh vs bash array indexing, globbing differences).

### 3.2 First-Line Header Formatting
Instead of raw JSON or arbitrary summary lines, standardize the tool block header format across AskTUI:
```
<tool_name> · <target/path/action> · <compact_parameters> · <duration/status>
```

#### Examples:
- **Shell**: `shell · git status · 42ms ✓`
- **Shell (with timeout/yield)**: `shell · npm run build · timeout 60s · 12.4s ✓`
- **Read**: `read · Sources/AskTUI/PromptEditor.swift · lines 10–45 · 1.2ms ✓`
- **Write**: `write · Sources/AskTools/JobTool.swift · 1.4 KB · 2.1ms ✓`
- **Job**: `job · job_2 · action: stop · 150ms ✓`

### 3.3 Unfolded Block Content & `cat << 'EOF'` Heredocs
- **Current Limitation**: When a block is unfolded in `ScreenComposer+Lines.swift`, it only renders `output`. The original command is truncated at 160 characters in `ToolSummary.swift`.
- **Design**:
  - Store `fullInput: String` in `Transcript.Item.tool`.
  - When unfolded (`!folded`), render a distinct command box above the output box:
    ```
    ┌─ command ────────────────────────────────────────────────────────┐
    │ cat << 'EOF' > test.py                                           │
    │ import sys                                                       │
    │ print(sys.version)                                               │
    │ EOF                                                              │
    └──────────────────────────────────────────────────────────────────┘
    ┌─ output ─────────────────────────────────────────────────────────┐
    │ (command produced no stdout)                                     │
    └──────────────────────────────────────────────────────────────────┘
    ```
  - **Heredoc Folding**: If a heredoc payload exceeds 50 lines, display the first 20 lines, a collapsed marker `[… 120 lines embedded heredoc …]`, and the closing delimiter, allowing full inspection only if explicitly expanded.

---

## 4. Context Tokens: Skills & MCP Servers at Session Start

### 4.1 Skills Context Optimization
- **Current State**: `SkillAdvertisement.block` appends every discovered skill to the system prompt, truncated at 1,024 characters each. A developer with 30 skills loses 4,000–8,000 tokens per turn before conversational messages begin.
- **Solution: Compact Advertisement vs. Search Index**:
  1. **Short-Form Advertisement**: Restrict the system prompt description to $\le 80$ characters:
     `- <name>: <short_summary> (<scope>)`
     This reduces context consumption by ~85%.
  2. **Dynamic Skill Loading**: When more than 16 skills are present, omit the skill list entirely from the system prompt. Instead, advertise the `skill` tool with an empty-argument query mode or a companion `skill_search` tool (matching the `mcp_search` model).

### 4.2 MCP Server Tool Definitions
- **Current State**: Servers with $\le 16$ tools have their full JSON schemas injected into `ModelRequest.tools`. Servers with $> 16$ tools shift to `mcp_search` and `mcp_call`.
- **Solution**:
  - Expose `maxDirectTools` per server in `config.json`.
  - Allow explicit `mode: "search" | "direct"` in `MCPServerSetting`.
  - Add session-scoped tool promotion: calling `mcp_search` registers the matched tools into the active session for the next turn, eliminating repeated `mcp_call` indirection.

---

## 5. Input Ergonomics, Slash Commands, and Steering

### 5.1 Alt/Option Word Navigation in Prompt Editor
- In `PromptEditor.swift`, implement:
  - `moveWordBackward()`: scan cursor backward past whitespace/punctuation to the start of the preceding word.
  - `moveWordForward()`: scan cursor forward past current word and whitespace to the start of the next word.
- Map `KeyEvent`:
  - `Key.left` with `.alt` $\to$ `moveWordBackward()`
  - `Key.right` with `.alt` $\to$ `moveWordForward()`
  - Terminal escape sequences `Esc + b` and `Esc + f`.
- In `ScreenController+InputSelection.swift`, support Shift+Option+Left/Right to select text by word boundaries.

### 5.2 Structured Slash Commands & Instant Choice Lists
- **Enter on `/model`**:
  - Currently, pressing Enter on `/model` sends an empty arguments command, printing a static table.
  - **New Behavior**: If a command has `takesChoices == true` and is submitted without arguments, do not execute the command. Immediately open its `CompletionPicker` in `.choices` mode (identical to typing `/model `).
- **Command Categories**:
  - Classify commands into `.session`, `.model`, `.tools`, and `.configuration`.
  - Render categorized group headers in the completion picker.

### 5.3 Queued Steering Replacement
- When a user types a message while the agent is running, `ScreenController+Queue.swift` adds a notice: `"Queued steering: <text>"`.
- **The Defect**: When the agent finishes its current turn and accepts the prompt via `promptAccepted(id:text:)`, the queued notice remains in the transcript as visual noise above the user's message.
- **Fix**: Store queued prompts with their ID in `Transcript.Item.queued(id:text:)`. Upon receiving `promptAccepted(id:text:)`, atomically replace the queued item in-place with `.user(text)` or remove it when appending at the tail.

---

## 6. Interactive Configuration & Session Resumption

### 6.1 Interactive Configuration Editor (`config.json`)
- Files: `~/.config/ask/config.json` (user) and `<project>/.ask/config.json` (project), formatted as JSON/JSON5 via `AemiJSON`.
- **Interactive TUI Flow**:
  - Up / Down: Move between settings keys (`ui.spinner`, `thinking`, `sandbox.network`, `maxTurns`).
  - Left / Right: Cycle through allowable options:
    - Booleans: `[✓ true] ◄ false ►`
    - Enums (`thinking`): `[off] ◄ low ► medium  high`
    - Spinners: `[line] ◄ dots ► block`
  - Enter: Commit and write atomically to `config.json` preserving indentation.

### 6.2 Session Exit Resume Banner
- When exiting ask cleanly (`/quit`, `Ctrl-D`, `Ctrl-C`):
  - In `AgentConversation.swift` (after `runInteractiveScreen` finishes):
    - Identify active session ID (`(session.path as NSString).lastPathComponent`).
    - Extract active launch flags via `source.flags.arguments`.
    - Print to standard output:
      ```sh
      Session saved to .ask/sessions/2026-10-27-01.jsonl
      To resume:
        ask --resume 2026-10-27-01 --model claude-3-7-sonnet
      ```
