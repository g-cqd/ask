---
status: not-started
blocked-by: []
date: 2026-11-13
---

# 0231 — Security audit 3, and a prompt-injection policy

Engineering plan phase D (note n33 asked for safeguards against prompt injection).

1. Audit 3: the threat model updated for what came after 2026-10-31 (MCP OAuth, session encryption and keyring, the search index,
   `#123`, the goal judge, `/loop`, threads and subagents, openers, `!!` commands, the forge's token, the Copilot sign-in), findings
   fixed test first.
2. A written policy: untrusted text (issue bodies, MCP and web results, files from elsewhere) cannot by itself cause anything that
   runs, writes, opens or sends; it is marked as such in the context; the goal judge is told the transcript may lie. A test per rule.
3. Roadmap 0183's research note (critical-software practices), SBOM and reproducible, signed releases weighed.

## Done when

The audit note lists every finding with its test, and the policy is in the white paper with its tests.
