---
status: accepted
date: 2026-10-29
---

# 0135 — Protections that ask: what runs later, and other tools' credentials

## Context

The security audit (2026-10-29, `development/research/security-audit-2026-10-29.md`) found that by default a command could plant code
that later runs outside the sandbox (findings 1 and 3) and read other tools' credentials (finding 2). The owner asked that these
refinements go behind the confirmation question and be tunable in the configuration, not be plain denials.

## Decision

1. **Askable protections.** `SandboxPolicy` keeps them in `denyRead` and `denyWrite`, so Seatbelt, the file tools' checks and the rename
   guards apply unchanged, and marks them `askable`. ask's own configuration and state directories are not askable: nothing lifts them.
2. **Unwritable, askable:** shell startup files, launch agents and daemons, login items, `~/.gitconfig` and `~/.config/git`, fish's
   configuration, `~/.ssh/authorized_keys`, `config`, `rc` and `environment` (not `known_hosts`), and in a workspace that already is a
   repository its `.git/hooks` and `.git/config` (a fresh workspace can still `git init`).
3. **Unreadable, askable:** the existing secret stores, plus gh, kube, docker, npm, pypi, gcloud, Azure, git's stored credentials,
   browsers' profiles and cookies, and other agents' sign-ins (named in the composition root, `OtherAgentsSecrets`, since they name
   providers).
4. **Asking:** a call's `sandbox` request naming such a place is put to the person (`writing <path> (protected: …)`), whatever the
   write and read scopes allow; allowed, the rules it names are lifted for that call, or for the session with "allow for the session".
   A read grant does not make a place writable. Refusals still say no more than before (ADR-0115).
5. **Tunable:** `sandbox.allowRead` (as before) and the new `sandbox.allowWrite` (absolute, `~/`, or relative to the project) lift a
   rule for good; the person's own file only.

## Consequences

- A command that runs into one fails with the system's error; the model has to ask again with a request. `gh`, `docker`, `kubectl`,
  `npm` with a `.npmrc`, `git push -u` and `git remote add` need their place allowed.
- ask's own executable is not protected: the owner builds ask with ask, and `/reload`'s self-check is what judges a new build.
- Not decided here: making the default write scope the workspace, and the default network (audit findings 1 and 2's open questions).
