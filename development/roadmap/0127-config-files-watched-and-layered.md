---
status: not-started
blocked-by: []
date: 2026-10-28
---

# 0127 — Configuration files are watched, and each layer adds to the ones above it

Owner wish (2026-10-28 23:02): when the sandbox allows it, watch every configuration file ask reads (the "ladder": user, project, and
any others) and apply a change while ask runs. A file lower in the ladder does not replace one above it; it adds to it and masks only
the keys it sets, unless a setting says otherwise.

## Still owed

- Today the files are read again before each prompt (ADR-0031); find what replacing versus layering does per section now (sections are
  layered key by key; check lists such as `mcp` servers and sandbox paths).
- Watching through FSEvents or a dispatch source (a system API, white paper rule), only for files the sandbox lets ask read.
- The setting that makes a layer replace instead of add, and its name.
