---
status: accepted
date: 2026-10-20
---

# 0058 — Provider lists supply limits without choosing a model

Originally numbered 0056 on the provider-listing branch; integration preserves the published selection ADR-0056
and sandbox ADR-0057 by assigning this record 0058. Its decision and evidence are unchanged.

## Context

Roadmaps 0038 and 0034 owe model lists and context windows for OpenAI-compatible providers. Codex already has an account's
priority list and can choose its first visible model (ADR-0037); that is not evidence that another service's first entry is
its preferred model. Nor does one field name for a context window describe all providers.

## The probes

Ledger: `docs/diary/2026-10-20-57.md`, including failed and inconclusive probes.

- Eleven keyless list requests: OpenRouter, Hugging Face's router and NVIDIA returned JSON lists; seven services refused
  authentication and Google's OpenAI root returned 404. A refusal does not establish an authenticated list's shape.
- The three successful lists use `data` with `id`, but disagree on limits. OpenRouter has a model window and a sometimes
  smaller top-provider window; Hugging Face has per-route windows; NVIDIA states none. No default marker was observed.
- All 683 initially observed ids contain `/`; 93 contain `:` and 19 begin with `~`. The old id validator refused them all.
- The release binary lists all three live services through isolated, keyless configured entries. A local fake-server
  script verifies that the cached window actually sizes the next inference request, and ordinary startup never fetches.
- Decoding a whole 468-model cache cost startup work; selecting one entry from AemiJSON's parsed tape reduced the observed
  cache/no-cache gap from 2.1 to 0.7 ms p50. This does not make discovery or the cache free.

## Decision

1. `ask models NAME` explicitly refreshes an OpenAI-compatible provider's `{baseURL}/models`, with the address, key and
   headers its inference requests use. Preset credential precedence and endpoint policy are unchanged. A custom keyless
   entry can list a public endpoint without a credential; presets still require their configured credential.
2. These lists **never choose a default**. Keep server order, show ids and reported limits, and require a configured model
   or `--model`. Codex's account-priority list and named connections retain their existing behaviour.
3. Use the smallest positive, believable context figure stated: `context_window`, `context_length`, the top-provider
   window, and live-route windows. An unknown route is not a zero and not a guarantee that the minimum known figure fits.
   Keep a positive top-provider output limit only when it is below the known window; otherwise leave it unknown.
   No reasoning level is inferred from a boolean capability field.
4. Model ids may include `/`, `:` and one leading `~`, within the existing 128-byte ceiling. They are ASCII terminal
   labels and JSON values, never paths. Alias and connection **names** retain the narrow plain-word rule.
5. A malformed record costs itself and is reported; a malformed optional figure costs only the figure. Invalid JSON, a
   missing list or no usable ids is an error. Bound network bodies to 4 MiB, cached files to 2 MiB and kept entries to 5000.
   Refusals expose only the status, not a potentially credential-bearing body.
6. Keep credential-free, owner-only caches beside the credentials as `models-NAME.json`, fresh for one day, scoped by the
   exact provider name, endpoint and whether a bearer key was supplied. This is **not account scope**: there is no account
   identifier in this protocol, and changing one nonempty key to another does not invalidate the cache. Refresh explicitly
   after switching keys or gateway routing headers. Unsafe filename names list without caching. Addresses containing
   user information, a query or a fragment also list without caching, with a notice: the address itself might carry a
   credential, so it must not be copied into a cache. This includes harmless query parameters; no secret-name guess is made.
7. Ordinary runs read only their selected entry from a fresh cache and never fetch or repair it. User-stated limits win
   field by field. Bad cache data is reported but does not refuse an otherwise valid explicit model. The full-cache read
   still validates all entries; the selected-entry read validates the header and selected entry, leaving intact models
   usable when another entry is damaged. Failed downloads preserve the old file; failed saves report the usable download.

## Consequences

- Live verification covers the three public lists, **not** authenticated model availability or inference. Spettro's window
  spelling has a synthetic test from research, not an authenticated observation. Roadmaps 0038/0034 stay in progress.
- Providers without a compatible list endpoint still accept explicit model ids. Google needs its own discovery adapter;
  the opencode session header and ant-ling authentication remain separate work.
- Cached limits can go stale or describe another key's account until explicit refresh or expiry. They guide budgeting,
  never authorize a request or certify account access; the provider remains authoritative.
- The binary and idle memory grow; the diary records before/after measurements rather than claiming zero cost.
