---
status: accepted
date: 2026-10-20
---

# 0047 — An opt-in read allow-list on a deny-default base

## Context

Roadmap 0042's last item: reads as an allow-list rather than a deny list. Seatbelt can only express that with a
`(deny default)` base, which then has to allow what every process needs. The owner decided: allow git's config by
default and do our best for it; list the sysctls rather than allowing all; opt-in or default at our discretion.

## Decision

- **Opt-in.** `sandbox.read`: `"workspace"`, `"anywhere"` (the default) or paths, with the rules of `write` (ADR-0043):
  every file narrows, `--read` widens, a session records it (ADR-0045). Unset, the profile is today's allow-default one,
  byte for byte, so nothing changes for anyone who does not ask.
- **When restricted**, commands run on `SeatbeltBase`: processes and same-sandbox signals; 43 named sysctls and six
  prefixes; 16 named mach services (user lookup, logging, notifications, certificate trust, preferences, the per-user
  temp directory); terminals and standard devices; metadata everywhere so paths resolve; file contents only under the
  system roots (`/bin`, `/sbin`, `/usr`, `/System`, `/Library`, `/private/etc`, `/private/var/db`, `/dev`,
  `/opt/homebrew`, Xcode, scratch). Then the chosen roots, the network level and the write scope as allowances, and
  the protections last, so a protected path inside a readable root stays protected.
- **Always readable when restricted**, for every home (the account's holds the toolchains, `$HOME` the configuration
  commands find): `~/Library/Developer/Toolchains`, `~/.swiftly`, `~/.gitconfig`, `~/.config/git`, the files those
  configs name in `[include]`/`[includeIf]` and `core.excludesFile` (one level; git treats an unreadable include as
  fatal), ssh's `config` and `known_hosts` (keys stay protected), and the user's `allowRead`.
- The read, write and edit tools apply the same allow-list in process, saying "outside the places this run may read".

Built by probing, with Codex 0.163.0's base profile as a catalogue, not a copy: its text is templated fragments
(one has an unbalanced paren) and its allowances were reviewed one by one (diary 43).

## Consequences

- A restricted command costs about 1.5 ms more to start (p50 ≈ 10.5 ms against 9.2 ms): `sandbox-exec` compiles a longer
  profile. Only when reads are restricted.
- Signed commits need `~/.gnupg`, a protected secret store in every mode: `allowRead: ['~/.gnupg']`.
- Tools that read the home directory (language caches, `~/.npmrc`, a second-level git include) need `allowRead`.
- Metadata is readable everywhere: names and sizes of files, not their contents.
- Scratch (`/private/var/folders`, `/private/tmp`) is readable and writable in every strict mode, as before.
