---
status: in-progress
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

## Steps 1 and 2 done (2026-11-13)

Audit 3: `development/research/security-audit-2026-11-13.md`. Eight findings, each fixed test first or against a live probe: a
repository's git configuration ran commands when ask was opened in it (Medium to High); `fetch` followed redirects unchecked, read
names not addresses, and read bodies whole; outside text could close its section and sat unmarked in the person's message; `#123`
left GitHub's answers in a cache on disk; the goal's judge spoke as the person; tests could reach the person's secrets.

The policy: ADR-0150 (text from outside is data), with `UntrustedText` and a test per entry. The white paper is at its 200 lines, so
the rule lives in the ADR and in the user guide (`docs/sandbox.md`, "Text from outside").

## Left

Step 3: roadmap 0183's research note (critical-software practices, an SBOM, signed and reproducible releases).
