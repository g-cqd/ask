---
status: not-started
blocked-by: []
date: 2026-10-28
---

# 0094 — The general config limits which providers serve a repository

Owner wish (2026-10-28 16:25): the general (user) config file can limit models exposure for a given repo to a chosen subset of the
configured providers. The rule can match by repo, git identity, filesystem location or git remote.

## Plan

- A user-config table `modelScopes`: a list of rules, each with a matcher (`path` glob, `remote` pattern, `identity` email or name) and the
  `providers` allowed. First matching rule wins; no match means no limit. It lives only in the **user** file: a project file must not
  widen or narrow what the user allows (the same trust rule as the sandbox, ADR on project trust).
- Applied in the same place as the 0089 filter (`ModelUsefulness` callers: `/model`, `ask models`, defaults), and an explicit
  `--provider` outside the allowed set is refused with a message naming the rule, so the limit is a policy and not a hint. State in the
  ADR whether `--model` can override (proposal: no, it cannot).
- Matching needs git facts: remote URL (`git remote get-url`), `user.email` of the repo. Read them once at start, cached, and tolerate a
  missing git (no match). Measure against the 50 ms cold-start budget; a subprocess may be too slow, in which case read `.git/config`.
- Tests: each matcher, precedence, no match, a project file cannot set it, refusal text.

## Not decided

The matcher grammar (glob versus regular expression; AemiRegex is deferred) and whether `identity` means the repo's `user.email` or
the signing key.
