---
status: not-started
blocked-by: []
date: 2026-11-01
---

# 0181 — Light indexing and semantic search over sessions, tasks and ideas

Wish (2026-11-01): our own indexer and tokenizers, for search within a session and the task list (0179, 0180), with semantic search,
"in the lightest way possible".

## Still owed

- Research: what an index of a long session costs (memory, build time) with a lexical index (AemiInterner, AemiText) against an
  embedding model on device (Apple's NaturalLanguage sentence embeddings), and whether the 20 MiB active budget allows either.
- A recommendation record before any code.
