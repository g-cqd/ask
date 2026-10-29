---
status: not-started
blocked-by: []
date: 2026-10-29
---

# 0150 — A tool middleware: providers' tool formats and native tools, to and from ask's

Owner wish (2026-10-29 17:55): "Create a tool middleware to translate tools and object formats from providers preferred formats and exposed
tools to ask ones and vice-versa."

## Owed

- **Map what exists:** ask already writes each provider's wire format for its own tools (AskAI's Anthropic, Responses, Codex,
  OpenAI-compatible, Agy and Copilot clients). What is missing is the layer between tool *vocabularies*: other agents' tools (Claude Code's
  `Bash`, `Read`, `Edit`, `Write`, `Glob`, `Grep`, 0146; Codex's `shell` and `apply_patch`; Gemini CLI's) and ask's (`bash`, `read`,
  `edit`, `write`, `find`, `grep`), arguments and results both ways.
- **Two uses:** converting sessions (0149), and offering a model the tool shapes it was trained on where that is measured to work better
  (an `apply_patch`-style edit for OpenAI models, say), each executed by ask's own tool under ask's sandbox and approvals.
- Measured before adopted: for each mapping a model would see, success and tokens on a fixed task set, against ask's own tools.
