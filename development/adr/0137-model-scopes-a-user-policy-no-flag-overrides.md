---
status: accepted
date: 2026-10-31
---

# 0137 — Model scopes: a policy in your own file that no flag overrides

## Context

The owner (2026-10-28) asked that the user's configuration limit which providers serve a repository, by its folder, its git remote
or its git identity. A work repository should reach models only through the work account. Roadmap 0094 left three questions open:
- whether `--model` or `--provider` can override a rule;
- the pattern grammar;
- what "identity" means.

## Decision

- **`modelScopes`, a list in the user's file only.** A project file holding it is refused, as for `approvals` and `credentials`: a
  repository must not choose which accounts it may reach, in either direction. The first rule that matches decides. When none
  matches, there is no limit.
- **A rule names `path`, `remote` or `identity`, at least one, and `providers`.** Every matcher it names must match. Unknown keys,
  empty patterns and an empty `providers` are refused when the file is read, not when a run needs the rule.
- **No flag overrides a rule.** A provider the person names (`--provider`, `--model` that resolves to it, `/model`) that the rule does
  not allow is refused, naming the rule's number and what it allows. Exit code 78, as for other configuration errors.
  - A provider a lower layer chose (the file's `provider`, a resumed session's destination, ask's automatic pick) gives way to the
    rule's first provider, with that provider's default model, and a detail line says so. Refusing those would make every run in
    a work repository fail until each project names a provider.
  - The way out is to edit the rule. That is the point: the rule exists for the times a flag would be typed by habit.
- **Globs, not regular expressions.** `*` is any run of characters, `/` included; `?` is one character; case is ignored; everything
  else is literal, so URLs and addresses need no escaping. AemiRegex is deferred, and a glob covers the examples
  (`*github.com?acme/*`, `*@acme.com`, `~/clients/*/app`). A path names its folder and everything beneath it, never a sibling that
  starts the same (`~/work` does not hold `~/workshop`).
- **Identity is `user.email` or `user.name` as git would take them,** not the signing key: the identity a repository commits as is
  what work and personal setups differ by, and a signing key is often absent. They are read from the repository's config, then
  `~/.gitconfig`, then the XDG git config, field by field. `include.path` and `includeIf "gitdir:…"` are followed where they stand,
  since a work address is most often set by an `includeIf`. Other conditions (`onbranch:`, `hasconfig:`) are not.
- **Git's files are read directly, without starting git.** A subprocess costs the cold-start budget. Reading takes the walk up to
  `.git`, a worktree's `gitdir` and `commondir`, and a small INI reader. Nothing is read when there are no rules.
- **Where it applies:** the resolution of every run's model (launch, `/model`, `/reload`), the `/model` list, the provider
  inference for an unqualified model id, and `ask models NAME`.

## Consequences

- A rule names connections and providers by their names: `codex` does not cover a second Codex account, `codex-2`; a rule lists
  each account it allows.
- `includeIf "gitdir:"` patterns are matched with the same glob, where `*` also crosses `/`. A pattern can therefore apply where git
  would not. In practice this over-applies a work address, the cautious direction.
- System git config (`/etc/gitconfig`) is not read.
- Cold start, measured with three rules that match nothing (every git file read): a median of 34–35 ms against 32.5 ms without
  rules, within the 50 ms budget.
