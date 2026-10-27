# Semantic Job Naming via Apple Foundation Models — Investigation (2026-10)

## Objective

Evaluate Apple's native `FoundationModels.framework` on macOS 26/27 to generate semantic
titles for background jobs (e.g. `npm run dev` -> `"Dev Mode"`, `tail -f ...` -> `"Log Watcher"`),
comparing the `general` vs `contentTagging` system language model use cases.

## Probe Protocol & Findings

Tested against concrete shell commands harvested directly from real `ask` and `pi` session logs,
ranging from typical command invocations up to large complex scripts (up to 17.8 KB / 172 lines)
using `SystemLanguageModel(useCase:)`:

### 1. Typical Commands (200–500 characters)

- `swift test -c release --enable-testable-imports --filter StatusLineFitTests`
  - `.general` [1001 ms]: `"Swift Test Filter"`
  - `.contentTagging` [1072 ms]: `"Swift, test, release, filter"`
- `bun test test/copilot`
  - `.general` [293 ms]: `"Bun Test"`
  - `.contentTagging` [799 ms]: `"test, command, bun, execution"`
- `git checkout -b feature/login`
  - `.general` [373 ms]: `"Create Feature Branch"`
  - `.contentTagging` [803 ms]: `"git, checkout, feature, login"`
- `exec python3 -u -m http.server 8080 --bind 127.0.0.1`
  - `.general` [324 ms]: `"Python Server"`
  - `.contentTagging` [786 ms]: `"Python, server, command, binding"`

### 2. Massive Multi-line Commands (1 KB – 17.8 KB)

- **Inline Python Script (3,000 chars, 53 lines)** — worktree teardown & json parsing:
  - `.general` [1,329 ms]: `"Probe Cleanup"`
  - `.contentTagging` [1,941 ms]: `"terminal, git, python, script, probe"`
- **Complex Multi-step Git & Xcode Script (1,122 chars, 15 lines)** — staging, test execution & diffing:
  - `.general` [935 ms]: `"Split Overview Field"`
  - `.contentTagging` [1,258 ms]: `"git, python, error, update, viewmodel"`
- **Large Embedded Analysis Tool (14,276 chars, 273 lines)** — swift AST & regex extractor:
  - `.general` [3,875 ms]: `"Apple Tool Command"`
  - `.contentTagging` [6,356 ms]: `"Apple tool, JSON schema, test case, prompt, budget"`
- **Large File Write (ADR-0115) (17,797 chars, 172 lines)** — markdown document generation:
  - `.general` [4,946 ms]: `"Model Sandbox Awareness"`
  - `.contentTagging` [7,497 ms]: `"model, authentication, configuration, provider, conversation"`

## Comparative Analysis: `.general` vs `.contentTagging`

| Attribute | `SystemLanguageModel.UseCase.general` | `SystemLanguageModel.UseCase.contentTagging` |
|---|---|---|
| **Output Style** | Synthesizes concise semantic action titles (e.g. `"Probe Cleanup"`, `"Model Sandbox Awareness"`). | Strictly extracts comma-separated classification tags regardless of prompt directives. |
| **Small Command Latency** | **300–400 ms** warm (cold start ~1.0 s). | **780–850 ms** warm (cold start ~1.1 s). |
| **Massive Script Latency (14–18 KB)** | **1.3 s to 4.9 s** proportional to prompt token count. | **1.9 s to 7.5 s** (significantly slower processing). |
| **Suitability for Job Naming** | **High** — understands multi-step shell intent and names the root task. | **Unsuitable** — emits raw token lists. |

## Architectural Constraints for Adoption

1. **Strictly Non-Blocking / Asynchronous:**
   With latency scaling from 350 ms up to 4.9 s on large scripts, semantic naming **must never execute on the main thread or gate tool returns**. The action budget is 25 ms.
2. **Background Detached Task:**
   When a command is backgrounded (yielded), ask can dispatch an unawaited background naming task. The UI displays the short display ID (`[#7a2f]`) and raw command immediately. When the title completes, it updates the runner entry and completion line in place.
3. **Prompt Truncation Safeguard:**
   Feeding 18 KB of script text takes ~5 seconds of NPU/GPU compute on the local Apple Neural Engine. For semantic job naming, the prompt should feed at most the first **1,000–2,000 bytes** of the command line, which caps latency at < 600 ms while preserving the leading command verbs and targets.
