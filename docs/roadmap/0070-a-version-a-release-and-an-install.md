---
status: not-started
blocked-by: ["the owner: whether ask is to be distributed as a binary at all"]
date: 2026-10-25
---

# 0070 — A version, a release and an install

The README says "No binary releases yet — build from source", and nothing in the project has a version: `ask --version` is an unknown option (probed today),
`Package.swift` carries no version, and the Antigravity identity string had to say `ask/0` because there was nothing to put there (ADR-0105). Building needs
Swift 6.4, macOS 26 and a clone. Anyone but the author starts at the wrong end.

## The work

1. **One version, one place**, read by `ask --version`, by the `user-agent` of every provider (today `ask`, and `ask/0 (Antigravity subscription connector)`), and recorded in each session file, so that a session names the build that wrote it
   (today it records a format version, not a build). The scheme is a decision (an ADR): a date, a counter or semantic versions.
2. **A release script** that builds the shipping binary (not the testable one, which the tests overwrite and which is larger), checks its size against the last release
   and runs the four budgets, and writes the binary, its checksum and the commit.
3. **An install path** the README can state in three lines, and an upgrade path: what happens to `~/.config/ask` and to sessions written by an older build (the session
   format is versioned and an upgrade keeps a backup, `SessionFile.swift`; what an *older* build does with a *newer* file is to be probed, not assumed).
4. **The signing question**, which only the owner can answer: a downloaded unsigned binary is quarantined by macOS; a signed and notarised one needs an Apple developer account.

## Done when

`ask --version` prints the version and the commit; every provider's identity carries it; a script produces a release directory from a clean checkout; and a probe in a fresh
user account (a throwaway `HOME`) installs it from that directory and runs `ask -p` with a fake provider. The size and budget numbers are in the diary.

## Not claimed

That anyone besides the owner wants a binary. That is the decision this entry waits for.
