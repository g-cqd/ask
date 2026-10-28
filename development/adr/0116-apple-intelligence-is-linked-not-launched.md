---
status: accepted
date: 2026-10-26
---

# 0116 — Apple's on-device model is linked into ask, not launched beside it

## Context

`g-cqd/pi-integrations` gives Pi the on-device model (`src/domains/apple-foundation/provider.ts`, 845 lines). Its design, read rather than assumed:

| Property | What `provider.ts` does |
|---|---|
| Getting at the framework | Embeds a Swift program as a string, writes it to `~/.cache/pi-integrations/apple-foundation/bridge.swift`, compiles it with `swiftc` on first use, and runs the Mach-O it produced |
| Trust | The binary is run with the person's authority from a user-writable cache; "up to date" means the sibling source file equals the embedded string, so whoever can write the cache can change both |
| Cost per request | One process spawn and a cold `LanguageModelSession` each time; the first request pays a compile (its own test needs a 30 s limit and skips off Apple Silicon) |
| Tool calls | The framework's tool calling is not used. A guided-generation struct holds `toolArgumentsJson` as a free **string**, which is then repaired (`parseToolArgumentsJson` strips fences and stray quotes), renamed through a synonym table (`filePath` → `path`), and a list of intent regexes (`WRITE_INTENT_RE`, `EXEC_INTENT_RE`, …) decides which tools the model is even shown |
| Streaming | Plain text streams; a response with tools is one block |
| The window | 4,096 tokens assumed; instructions cut to 1,800 characters, the prompt to its last 6,000, tool schemas as JSON in the instructions; no token count; usage is characters ÷ 4 |
| Robustness | `stderr` is piped and never read; no timeout; every line is `JSON.parse`d unguarded |
| Selection | Sets a placeholder `apiKey` so Pi lists it as available |

## Decision

ask links `FoundationModels` and calls it in process (`Sources/AskApple`, its own target so a library's tests never load it).

1. **No compiler, no helper, no cache, no process.** Nothing is written and then executed. The first request pays no compile and no spawn.
2. **Tool arguments are generated under constraint.** Each tool's JSON Schema becomes a `GenerationSchema` (objects, arrays, strings, numbers, integers, booleans, string enums; optional by `required`). The framework's
   own tool calling produces the arguments as typed values; no repair, no synonym table. The tool the framework calls does not run: it records the call and throws, which ends the response, and the call goes back to ask's
   loop to run under the sandbox like any other provider's. The `sandbox` argument every tool takes is left out of what the model sees: it is a token spent on something a three-billion-parameter model cannot use.
3. **Which tools to offer is a budget, not a guess.** Tools are offered in the loop's order while their estimated cost fits a third of the window; the composition root withholds `narrow_sandbox`. No intent regex.
4. **The window is measured.** The conversation's newest turns are kept whole and the oldest dropped, tool results cut in the middle, and, where the system can count (macOS 26.4), `tokenCount` verifies the whole request and
   the prompt is cut again until it fits. A window overflow becomes `ProviderFailure.contextOverflow`, so the loop compacts instead of retrying.
5. **It is the default when nothing else can answer.** With no flag, configuration or sign-in, ask uses Claude, Codex or Antigravity if signed in, else the on-device model (`AutoProvider`). It is chosen **by name**; whether it can
   answer is learned by the first request, which says why and how to sign in instead.
6. It is a built-in provider named `apple` with one model, `on-device`: `--provider apple`, `ask models apple`, `/model apple on-device`, listed beside every other account in `/model`.

## Evidence

| Claim | Probe | Result |
|---|---|---|
| The framework answers in process, here | `ask --provider apple -p "…capital of France?"` | "Paris is the capital of France.", 689 input tokens, 3.9 s wall including process start |
| A tool call comes back as a call and the loop runs it | `ask --provider apple -p "Read the file notes.txt …"` | `read {"path": "notes.txt"}` ran under the sandbox; the next turn answered from its result |
| Wiring, order of events, a typed tool call, and an oversize conversation | `AppleProviderLiveTests` (3, skipped where Apple Intelligence is off) | Pass; the 70 KB conversation is cut to fit and answered |
| The pure parts: turns, budget, cut, schema, footprint, capture, failure mapping | 27 tests in `AskAppleTests` (30 with the live ones) | Pass |
| Asking the system whether the model is available loads its stack | idle RSS, three interleaved runs, no account (apple selected by name): 11.9 MB; with the availability check at launch: 19.3 MB; base 10.0 MB | **Confirmed**: 6.3 MB. So launch never asks (`AutoProvider`, `withAppleLimits` use names and constants) |
| Linking costs something | idle RSS with the framework linked and never touched: 11.9 MB against 10.0 MB (+1.9 MB); cold start median 26.3 / 25.3 / 26.7 ms against 24.5 / 25.2 / 25.6 (about +1 ms, three interleaved pairs under load; the base is itself at the 25 ms line) | Measured; inside the memory budget (24 MB), at the cold-start line the base already touches |
| The framework can be loaded lazily | `-Xlinker -lazy_framework FoundationModels` with `-disable-autolink-framework` | **Refused by the linker**: `lazy-load will be ignored … because deployment target version is too low`. Reverted; the cost above stands |
| A hostile-looking prompt fails cleanly | a 100 KB conversation of one repeated word, through the provider | The framework's guardrail refused it (`May contain unsafe content`), surfacing **unmapped** on macOS 27, where the type is `LanguageModelError`, not `GenerationError`. Both are mapped now (`AppleFailureTests`); the live test uses prose, and the 70 KB of prose is cut to fit and answered |

## Consequences

- ask now links `FoundationModels` (macOS 26 floor, as the package already declares) and pays the measured +1.9 MB and about a millisecond.
- The failure types differ by OS: macOS 27 reports `LanguageModelError`, earlier `GenerationError`; both are mapped.
- Not done, and said: streaming of the tool-call arguments (the call arrives whole, because the framework runs the tool once the arguments are complete), the content-tagging use case pi-integrations also exposes (a
  classifier, not a chat model, so not a provider here), and a session that keeps its prefix warm between requests (each request is a fresh session over ask's own history; whether the system caches the prefix is unprobed).
