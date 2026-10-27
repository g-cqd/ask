# Semantic Job Naming via Apple Foundation Models — Investigation (2026-10)

## Objective

Evaluate Apple's native `FoundationModels.framework` on macOS 26/27 to generate semantic
titles for background jobs (e.g. `npm run dev` -> `"Dev Mode"`, `tail -f ...` -> `"Log Watcher"`),
comparing the `general` vs `contentTagging` system language model use cases.

## Probe Protocol & Findings

Tested against concrete shell command patterns using `SystemLanguageModel(useCase:)`:

1. **`SystemLanguageModel.UseCase.general`:**
   - Synthesizes readable titles:
     - `npm run dev -- --port 8080` -> `"Dev Mode"`
     - `git checkout -b feature/login` -> `"Feature Branch"`
     - `swift test -c release --filter RunnerTests` -> `"Swift Test Release Filter"`
     - `tail -f /var/log/system.log` -> `"Log Watcher"`
     - `exec python3 -u -m http.server 8080 --bind 127.0.0.1` -> `"Python Server"`
     - `docker compose up -d database redis` -> `"Service Startup"`
   - Latency: **320–450 ms** warm (first call ~1295 ms).

2. **`SystemLanguageModel.UseCase.contentTagging`:**
   - Specially fine-tuned for extracting comma-separated keywords/tags:
     - `npm run dev -- --port 8080` -> `"development, command, port, npm"`
     - `git checkout -b feature/login` -> `"git, checkout, feature, login"`
     - `tail -f /var/log/system.log` -> `"log, monitoring, file, tail"`
   - Even when prompted specifically for a title, it outputs comma-separated tags (`"server, python, binding"`).
   - Latency: **700–850 ms** warm (first call ~1160 ms).

## Architectural Verdict & Constraints for Adoption

- `contentTagging` is **unsuitable for UI titles**; it generates classification tags, not titles.
- `general` produces clear semantic titles.
- **Cost/Budget Impact:**
  - Synchronous naming on the tool call path is **strictly unacceptable**: 350 ms exceeds the entire action-to-action latency budget (25 ms).
  - Background jobs are already asynchronous: naming must run in an unawaited detached background task, updating the runner's title only when ready.
  - If the model is busy, unavailable, or times out (>1.5 s), the title remains the command detail.
