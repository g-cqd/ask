---
status: accepted
amends: ADR-0057
date: 2026-11-17
---

# 0162 — A call keeps its narrowing for the session: no tool of its own

## Context

A model had two ways to reach the sandbox: the `sandbox` argument of `read`, `write` and `bash` (ADR-0054), for one call, and the
`narrow_sandbox` tool (ADR-0057), for every later call. The tool took the same `sandbox` object, and a `reset`.

What the sessions on this machine say (`Scripts/measure-tool-arguments.py`, 47,227 calls):

| | Calls |
|---|---|
| `sandbox` given to `bash` | 840, of which 827 are `network: any`: asking for more |
| `sandbox` given to `read`, to `write` | 1, 1 |
| `narrow_sandbox` | 5: one asked for more, four were `reset` |

The tool cost 755 bytes of every request and was never once used to narrow a session. The capability is still worth having:
it is the one thing a model can do to make the rest of a conversation safer, and ADR-0115 kept it on purpose.

## Decision

**`narrow_sandbox` is no longer a tool. The `sandbox` argument takes `session`: `keep` or `reset`.**

1. **`session: keep`** makes the call's narrowing every later call's too. The call itself runs under it, and its result starts
   with `Narrowed for the rest of the session.`
2. **`session: reset`** asks the person for the run's own sandbox back; the call then runs under it, and says
   `The session's narrowing is undone.` With nothing to undo it says so and asks no one.
3. **Everything ADR-0057 decided stands**, moved from the tool into `ToolRegistry`: a later `keep` of one dimension keeps the
   others; what is kept never reaches past the run's ceiling; a reset always asks and no remembered grant covers it; under
   `-p` it is refused; the session is not narrowed while a job runs; `/new` and `/resume` clear it.
4. **A call that cannot keep what it asked does not run.** `keep` with a job running, with no dimension to keep, or with a
   word that is neither, is refused with why, before the command is started: a model that asked for "from now on" is not left
   believing it.
5. **A grant remembers no session.** What the person allows "for the session" is the network, write and read asked for, as
   before: `session` is taken off the request before it is put to them.
6. **The schema names `session` on `bash` only**, where 840 of the 842 `sandbox` arguments were given. The registry honours
   it on any of ask's tools; `read` and `write` keep the shorter text, 377 bytes each.

The registry learns whether something still runs from a closure the composition gives it (`busy`): `AskAgentCore` does not
know `JobTable`, and should not.

This amends ADR-0057's points 1 and 3 (the tool, and the shape of a reset). ADR-0115's point 6 now reads: the call that
keeps a narrowing is told `Narrowed for the rest of the session.` and nothing of the policy.

## The probes

| Claim | Probe | Verdict |
|---|---|---|
| The tool list shrinks | `Scripts/measure-request-size.py` | **Holds**: 11,381 to 10,776 bytes; `bash` 1,871 to 2,022 |
| Every case the tool's tests pinned still holds | `SessionSandboxRequestTests`: eight cases ported, four new | **Holds** |
| The new tests can fail | The job check, the run's ceiling, the grant's request and the reset's context each taken out | **Holds**: five of twelve fail |
| The real binary refuses `keep` while a job runs | `probe-agent-run` X, with a `sleep` job, then stopped | **Holds**; it failed first on a binary built without the check |
| On the screen a reset still asks, `/model` keeps the narrowing and `/new` drops it | `probe-interactive` Y and Z, rewritten to `bash` calls | **Holds** |

## Consequences

- A model that wants only to narrow the session must still call something: `bash` with `:` does it. That is one word more
  than the tool took, and the common case, narrowing with the first command it matters for, is one call fewer.
- **Not known: whether a model finds `session` in an argument's description.** It never used the tool either, so there is no
  rate to fall from; `Scripts/measure-tool-arguments.py bash --values sandbox` shows it in later sessions.
- A session recorded with `narrow_sandbox` calls replays as it was.
- `docs/sandbox.md` is unchanged: what a person can see and is asked is the same.
