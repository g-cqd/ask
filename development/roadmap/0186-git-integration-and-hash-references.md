---
status: not-started
blocked-by: []
date: 2026-11-01
---

# 0186 — A git integration: the workspace's state in the screen and for the model, and `#` for pull requests, issues and tasks

Owner (2026-11-01): a git integration that polls, from the workspace's git setup, the information worth showing in the screen and
passing to the model; and `#` designating pull requests, issues or tasks.

## Still owed

- A research note first: what to show (branch, ahead/behind, dirty files, the current pull request and its checks), where it comes from
  (git itself; a forge's API through `gh`-like credentials, which ask must not borrow from another tool's keychain entries; MCP servers
  that already speak to forges), how often to poll without costing idle memory or the cold start (50 ms), and what the sandbox allows.
- The model's side: what it is told, and when (a line in the context, or a tool it calls, as the task list is: 0179).
- `#` in the input grammar (0048): a third sigil, for things that are tracked: `#123` a pull request or issue, `#t5` a task (0179).
  Decide the forms with the owner, and keep `#` inside a word, and a Markdown heading at a line's start, as text.
