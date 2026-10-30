---
status: not-started
blocked-by: []
date: 2026-10-30
---

# 0155 — Setting up allowances for the tools people use (later)

Owner (2026-10-30): leave the setup topics for later. Since ADR-0135, `gh`, `docker`, `kubectl`, `npm` with a `.npmrc`, `git push -u`
and `git remote add` fail under the sandbox until their place is allowed (`sandbox.allowRead`, `sandbox.allowWrite`) or a call asks for it.

## Later

- A first-run or `/config` step that sees which of these tools are installed and offers their allowances, one by one.
- A clearer failure: when a command fails on a protected place, say which allowance would let it, to the person (not the model, ADR-0115).
- Decide whether `.git/config` writes by git itself (`push -u`, `remote add`, `branch -u`) deserve a narrower rule than the whole file.
