---
status: accepted
date: 2026-10-25
---

# 0098 — The Antigravity model list is cached for its project and read by a run, never fetched

## Context

ADR-0097 left a gap it named: a run did not know the model's window, so the loop used its 16,384-token reply cap and compacted only when
a request was refused for length, and Cloud Code's wording for that refusal has never been seen. Nothing at startup may touch the network,
so the answer is the one the other providers use: a list fetched by `ask models NAME`, kept, and read by the runs that follow.

## The probes

- **Without a cache** (a temporary line printing what the run resolved, removed again): window unknown, reply cap 16,384, compaction at
  ask's own 150,000. **Observed.**
- **After `ask models agy`**, which wrote `models-agy.json` (mode 0600, 2,349 bytes, no token): `gpt-oss-120b-medium` resolved a window of 131,072,
  an output limit of 32,768, a reply cap of 32,768 and compaction at **85,197**, which is before the window. `gemini-3-flash` resolved
  1,048,576 and 65,536, and compaction stayed at 150,000, because a threshold the user or default asked for is never raised. **Observed.**
- **A model the list does not name** (`gemini-3-flash-nonesuch`): the run goes ahead with no window and the server answers HTTP 404
  "Requested entity was not found", which is shown with exit 69. **Observed.** It is not warned about in advance.
- **Ten unit tests** over the recorded list: a refresh keeps and returns it; a read sends nothing; one entry is read without the others, and a
  damaged entry elsewhere costs it nothing; nothing is read for a stranger (signed out, not yet onboarded, another project, a day old);
  a damaged cache is reported and never rewritten; a failed download leaves the cache as it was; an expired token is refreshed first; a
  cache that cannot be written is a notice with the list still returned; and the file holds no token or secret.

## Decision

1. **The scope is the project.** A cached list names the provider, the Cloud Code project it was requested for and the endpoint
   (`…:fetchAvailableModels`, which has no query), and is read only by the same project. It is never a fallback for another account.
2. **Freshness is the shared one** (a day), and it sits in `models-agy.json` beside the credentials, as the other lists do.
3. **A run reads, and reads one entry.** It looks up only its own model, reads the stored sign-in without refreshing it, sends nothing and
   repairs nothing. A missing, stale or foreign cache is silent and the run goes ahead as before. The server's default is not cached; it is
   shown by the fresh listing that `ask models agy` prints.
4. **`ask models agy` is the only fetch.** It refreshes a token and onboards if it has to, downloads, and keeps the list; a cache that
   cannot be written is a notice, not a failure.
5. **The listing stays ask's own rule** from ADR-0087 (chat models only); nothing about it changes here.

## Consequences

- A run that follows `ask models agy` knows its window and compacts before the server refuses; a run that does not still relies on a
  refusal nobody has seen. After a day the knowledge lapses until the list is fetched again, and nothing says so.
- The first run on a machine has no list. Whether the first request should fetch one (the token and project are in hand by then) is a
  different design, with a request's latency as its cost, and is not done.
- Reading the cache costs one read of a small file and the stored sign-in. The default path (any other provider) never constructs it; the
  cost on an `agy` start was not measured.
- Named connections, a second account, and the interactive screen with `agy` remain as ADR-0097 left them.
