---
status: accepted
date: 2026-10-19
---

# 0032 — Configuration is JSON or JSON5 in layers, and a project's file needs trust

## Context

ask had flags and one provider file. Settings that belong to a person or a project (the model, the turn limit,
when to compact) had nowhere to live, and changing them meant restarting. Roadmap 0039; the user chose JSON
that AemiJSON can speak, JSON5 for example, to be probed first, and files named `.json` that may hold either.

## Format: probed first

AemiJSON's JSON5 mode against the reference `json5` 2.2.3, run under bun, on 51 JSON5 cases (comments, unquoted
and single-quoted keys, trailing commas, hex, `Infinity`, `NaN`, escapes, line continuations) and 10 strict-JSON
cases, with Foundation's `allowsJSON5` as a second opinion.

| | Agree with the reference |
|---|---|
| AemiJSON, JSON5 mode | 49 of 51 |
| Foundation, JSON5 mode | 47 of 51 |
| Strict JSON through AemiJSON in strict and in JSON5 mode | 10 of 10, apart from how the numbers are printed |

The strict-JSON claim excludes number formatting: AemiJSON decodes an integer-valued number as a `Double`, which
prints as `2000.0`. That is a rendering difference in the probe, not a difference in value.

One apparent disagreement was my probe's bug: it escaped non-ASCII text by scalar instead of by UTF-16 unit.
The three real defects were filed with AemiJSON, as the user asked, not worked around:
- [#1](https://github.com/g-cqd/AemiJSON/issues/1): Unicode whitespace and U+2028/U+2029 are rejected in JSON5.
- [#2](https://github.com/g-cqd/AemiJSON/issues/2): JSON5 accepts numbers with a leading zero.
- [#3](https://github.com/g-cqd/AemiJSON/issues/3): `.throwError` misses duplicate keys that differ only by escapes,
  and the first of them wins.

None changes how a configuration file reads in practice. The third matters for a typo'd duplicate key, which
the escaped spelling would not trigger by accident.

## Decision

- **One reader, JSON5 mode, duplicate keys refused.** Plain JSON parses identically in that mode, so a file
  named `config.json` may hold either. Unknown keys, wrong types and out-of-range values are refused too: a
  typo that silently does nothing is worse than an error.
- **Layers, lowest first:** defaults, `~/.config/ask/config.json`, a trusted `<project>/.ask/config.json`,
  `ASK_*` environment variables, flags. A higher layer replaces the keys it sets. `ask config` shows each value
  and its source.
- **Keys today:** `model`, `provider`, `maxTurns`, `compactAt`. More arrive with the features that need them.
- **Validated whole.** Every layer is read and the model resolved before anything changes, so a half-edited
  file cannot leave ask half-configured.
- **Reload is at each prompt,** not by watching. Reading two small files costs 94 µs, once per prompt, and
  needs no thread, no event, and no debounce. A valid change takes effect on that prompt and is announced with
  old value, new value and source. An invalid one is announced once, and the previous settings stay. The
  kqueue watcher is for binary reload, where a rebuild must be noticed while ask is idle.

## Trust

A project's file is text from a repository. It applies only after `ask trust`, and only for the bytes trusted:
the store keeps its path and SHA-256, as `direnv allow` does, so a `git pull` that changes the file untrusts it
until the user looks again. An untrusted or changed file is not parsed at all, and a notice says how to use it.
The store is owner-only, and a corrupt one is an error, not an empty store.

**What this does not stop.** The agent has a bash tool, and nothing yet denies it the config paths. It can edit
`~/.config/ask/config.json`, and could run `ask trust`. `ask trust` therefore refuses without a terminal on
standard input, which the agent's bash does not have; the real model, told to run it, got exit 77. That is a
speed bump, not a wall: a pty can be allocated. Denying `~/.config/ask/` and every `.ask/` to the agent is the
sandbox's work (ADR-0020, roadmap 0017), and it must land before a project file can carry anything dangerous.
Today's keys cannot: the worst a project file can do is pick a model, a provider that already exists in the
user's own `providers.json`, and two limits.

## Cost (ADR-0016)

| | Result |
|---|---|
| Load, no files | 15 µs, 2 syscalls |
| Load, user file, trusted project file, environment | 94 µs, 14 syscalls |
| Cold start, no files, 200 interleaved runs | p50 9.07 → 9.14 ms, p90 equal |

## Consequences

- A flag given after a subcommand does not reach `ask config`, which shows the files and the environment, not
  the flags.
- A setting changed by reload that needs a different provider rebuilds the loop on the next prompt. A run in
  progress keeps what it started with.
- The probe emulator now handles the scroll region. The transcript has used one since the other session's work,
  and an emulator that ignored it drew every new line over the last, which probes that read only the newest line
  never noticed.
