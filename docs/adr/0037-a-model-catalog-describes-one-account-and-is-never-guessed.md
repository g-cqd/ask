---
status: accepted
date: 2026-10-20
---

# 0037 — A model catalog describes one account, is read explicitly, and is never guessed

## Context

A ChatGPT subscription refused `gpt-5.5`, which pi's static catalog lists (diary 27). A static list describes no
account. Users also want several accounts of one provider (roadmap 0046), so whatever discovery stores must already be
bound to an account and endpoint, or the second account would inherit the first one's models.

## The probes

Ledger in `docs/diary/2026-10-20-28.md`.

- **Does `GET /backend-api/codex/models` answer with ask's credentials?** **REFUTED as pi-integrations wrote it**: HTTP
  400, `client_version` required. **CONFIRMED with `?client_version=0.163.0`**: HTTP 200, 569,148 bytes, nine models,
  seven visible. `gpt-5.5` is absent. Reasoning levels are objects, not strings. No entry reports an output limit.
- **Does the release binary use it end to end?** `ask models codex` listed the seven; `ask --provider codex --print`
  with no `--model` announced `codex/gpt-6.1-sol` from the catalog and answered. Observed on one account.

## Decision

1. The catalog is read from the provider for the signed-in account, never taken from a bundled list. An explicit
   `--model`, then configuration, then the catalog's first visible text model, in that order. Explicit ids need no
   network and are never replaced because a catalog omitted them.
2. The cache stores only model ids and limits, never the response's instructions or any credential, in an owner-only file,
   keyed by provider, remote account id and the exact endpoint including its version query. Another account, endpoint
   or version is a miss. It expires after a day, and a date in the future is not fresh.
3. Reading never writes or repairs. A damaged cache is reported and not used; a successful download is still used when it
   cannot be cached, with a notice. `ask models codex` is the explicit refresh. A failed refresh leaves the old cache and
   is not answered from it.
4. A failure of discovery says to pass `--model`, and names the status, never the server's body. There is no static
   fallback list: it is the stale-catalog problem discovery exists to remove.
5. Limits come from the catalog's normal `context_window`, not the larger `max_context_window`, which the server
   documents nothing about. A limit the catalog does not report is unknown, not invented.
6. Ordinary startup never fetches: only a Codex run with no model named consults the cache or the network.

## Consequences

- The `client_version` the server requires is the installed Codex CLI's, a fact about the server's schema and not ask's
  identity. It is a constant in one place and will need updating if the server rejects it.
- The cache has a small near-duplicate of credential-file atomic writing, accepted in the analyzer. Whether both should
  share one transaction owner is roadmap 0045, because accounts make concurrent writers real.
- Other providers still require `--model`; Spettro and the presets are roadmap 0038's remainder.
- Reasoning levels and per-account aliases are not modelled yet (roadmaps 0043, 0047).
