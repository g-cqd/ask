---
status: not-started
blocked-by: []
date: 2026-10-27
---

# 0076 — Reusable algorithms are owned by Aemi subpackages

Any reusable algorithm needed by ask must be reused from, or promoted into, the
appropriate Aemi subpackage rather than implemented as an ask-local copy. This
applies to search, typo-tolerant matching, edit distance, ranking primitives,
indexing, compression, and future algorithmic needs—not only the current skills
search. Ask keeps application policy: which skills/tools are eligible, security
filters, relevance weights, thresholds and UI presentation.

## Still owed

- Before implementing an algorithm, inspect the Aemi subpackages and other local
  implementations (including the user's AD* family where available). Prefer an
  existing tested implementation; do not copy its source into ask.
- Inventory reusable algorithms currently in ask; promote missing primitives into
  the most specific Aemi subpackage, without creating an umbrella dependency.
- Put new general fuzzy-search/ranking/indexing primitives in AemiText (or the
  appropriate specialized subpackage). Keep permission filtering outside ranking.
- Add red-first boundary, Unicode, adversarial-input and equivalence tests in the
  owning package, and release benchmarks before pinning the consumer revision.
- Verify upstream builds/tests and the explicit/resolved dependency pins together;
  migrate ask to consume the API and remove redundant local implementations.
- Record each adoption or promotion with owner, probe results, measured cost and
  remaining migrations. Existing Aemi algorithms need adoption, not duplication.

The current skill-search task found bounded Levenshtein `AemiText.editDistance`
already present at ask's pinned Aemi revision; it requires no new distance kernel.
