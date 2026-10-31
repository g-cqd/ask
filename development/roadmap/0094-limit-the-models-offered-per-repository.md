---
status: done
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

## Done

Decided in ADR-0137: globs; `user.email` or `user.name` as identity; no flag overrides a rule. A provider a file, a resumed session or
ask's own pick chose gives way to the rule's first provider instead of failing the run.

- AskAgentCore `ModelScopes/`: `ModelScope`, `ScopeGlob`, `ModelScopeMatch` (`allows`, `verdict`, `refusal`), `ModelScopeVerdict`,
  `RepositoryFacts.read` and `GitConfigFile` (remotes, identity, `include` and `includeIf "gitdir:"`, worktrees). Decoding and the
  project refusal are in `ConfigurationFile+ModelScopes.swift`, and `Configuration.modelScope(for:)` gives the first match.
- `ask`: `ModelScopeGate`, and `ConfigurationSource.resolveWithinScope` for launch, `/model` and reload. The `/model` list,
  `ModelQualifier.infer` and `ask models NAME` filter or refuse too.
- Tests: `ModelScopeTests` (9) and `RepositoryFactsTests` (5). Catalog row, the generated example, and `docs/configuration.md`.
- Probe `Scripts/probe-model-scopes.py`, 12 checks with a control for each refusal: `--provider` refused before any request and
  answered outside the rule; `ask models anthropic` and `claude` refused; the file's default replaced at start; `/model` listing only
  the allowed accounts and refusing another.
- Cold start, three non-matching rules: a median of 34–35 ms against 32.5 ms without rules.

Not verified: a real work/personal setup with real accounts; a submodule's `.git` file (handled like a worktree's, no test);
`/reload` after editing the rules in a real terminal.
