# Roadmap reassessment, 2026-10-28

The owner asked for the whole roadmap and every wish to be reassessed, with the cheap UI refinements to do before the big tasks. Every
wish in `ask-wishes.md` up to 23:11 has a roadmap item; the newest are 0123 to 0130. Items marked done are left out.

## 1. Defects the owner flagged (fix first, hours)

- **0124** four cells before a block's trailing status: a regression from 0080, which set the gap to two.
- **0125** Page Up scrolls past the first block into empty screens.

## 2. Cheap UI refinements (each an hour or a few, independent of each other)

| Item | What | Needs from the owner |
| --- | --- | --- |
| 0129 | Running tools grey, user blocks blue, queued steering grey without background and with a spinner | nothing |
| 0128 | The home folder shown as `~`, never inside file content or commands | nothing |
| 0097 + 0112 | `/continue` and bare "continue"; Right twice on an empty input sends it | nothing |
| 0105 | A compaction as a foldable block with its summary | nothing |
| 0093 | `/tree` with a selector | nothing |
| 0126 | A shorter timeout in command headers | pick a form (`⏱2m`, `2m`, `≤2m`) |
| 0106 | ask's own blocks tinted purple | the details, asked earlier |
| 0111 | Prompt history with Up and Down | the edit rule's detail; a few hours more than the others |

## 3. Budgets and quality (rules, not wishes)

- **0088** active memory measured 21.5 to 22.9 MiB against 20 MiB: the one budget broken today.
- 0054 cold-start variance, 0028 audit gaps, 0079 review findings, 0025 file splits: leftovers, none blocking.

## 4. MCP (critical per the owner)

- **0123** every version, three transports (adding HTTP with SSE), the official conformance suite, resources and the other features, a
  head-to-head with the official Swift SDK in `MCPStress`. Big: several sessions. apple-docs' public instance already works (0114).
- 0114's remaining part (REA, daily use) folds into 0123's real-server checks.

## 5. Configuration and commands (decisions first)

- 0118 typed settings (which mixed keys to retype: `maxTurns`, `compactAt`, the `"on"`/`"off"` booleans), 0127 watching and layering,
  0096 a generated full example, 0094 model scopes, 0113 commands at the next turn (an assessment table for the owner).

## 6. Accounts and security

- 0110 keys in the keychain, 0092 a second login adds an account. Sandbox research 0020, 0021, 0022 stays research.

## 7. Bigger features

- 0116 picker as confirmation and 0117 the question tool (one design, shared), 0115 taking over a running session, 0107 debug mode, 0063
  subagents, 0066 Mermaid.

## 8. The Aemi family

- 0086 finish AemiMarkdown (the owner asked for it to be finished) with 0065 markdown in the transcript, 0087 promote AtelierLexers,
  0077 AemiRegex everywhere, 0109 AemiHMMML, then 0130 MDM on top of it, 0122 Protobuf (blocked on AemiProtobuf's roadmap), 0121
  event-driven investigation, 0076 and 0059.

## 9. Parked

Provider items that need keys or accounts to probe (0010, 0034, 0038, 0040, 0046, 0047, 0052, 0053, 0055, 0069, 0073); 0070 distribution
(not relevant yet, per the owner); 0012 codemode (shelved); 0033 the extension host (hooks only); 0014 and 0015 the pixel UI. Long-running
items with small leftovers (0003, 0016, 0027, 0043, 0048, 0049, 0051, 0061, 0062, 0064, 0067, 0068, 0074, 0075, 0101) are finished when
the work above touches them.

## Proposed order

1. 0124 and 0125, now.
2. The cheap UI wave: 0129, 0128, 0097 with 0112, 0105, 0093; 0126 and 0106 once their forms are chosen.
3. 0088, so every budget holds before more is added.
4. 0123, the MCP program.
5. 0086 with 0065, then 0087.
6. The decision items (0113, 0118), then 0127, 0110, 0111, 0116 with 0117.
7. Investigations: 0115, 0107, 0121; 0109 then 0130.
