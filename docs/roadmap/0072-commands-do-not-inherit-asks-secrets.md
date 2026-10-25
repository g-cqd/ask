---
status: done
blocked-by: []
date: 2026-10-25
---

# 0072 — Commands the model runs do not inherit ask's secrets

Item 13 of roadmap 0028 said "the bash tool passes the whole environment to commands, including `ANTHROPIC_API_KEY`; decide with the sandbox work whether to scrub it". It was
filed in a catch-all and nothing came of it. **Probed today** with `Scripts/probe-bash-environment.py`: a command the model runs sees `ANTHROPIC_API_KEY` and any other variable in ask's
environment, and **the value comes back in the tool result, which is sent to the provider**. The sandbox protects secret *files* (ADR-0035: the credential file, the session directory);
it does nothing for the environment. A model that is merely curious, or a file it was told to read that contains an instruction, can read every key the person exported, and a transcript or a
provider log then holds it.

This is the one defect found in the reassessment (`docs/research/reassessment-2026-10-25.md`) that is a security exposure rather than a missing feature.

## The decision to make first (an ADR)

- **Deny the variables ask itself reads credentials from**: `ANTHROPIC_API_KEY`, `ANTHROPIC_AUTH_TOKEN`, `ANTHROPIC_OAUTH_TOKEN`, each preset's key variable (`ProviderPreset.keyVariable`), and
  `ASK_*`. ask knows this list exactly, so it costs a person nothing they did not already give ask. Everything else is inherited as today.
- **Allow only a short list** (`PATH`, `HOME`, `LANG`, `TERM`, …). Safer, and it breaks `gh`, `aws`, `npm` and every workflow that uses a variable; the cost is real and unmeasured.
- Either way a **setting** in the configuration lets a person pass a named variable through, or withhold one more, and a command's environment is **shown** in `/config` so that nothing is silent.

The first is the default to probe; it closes the exposure ask itself created without pretending to know which of a person's other variables are secrets.

## The work

1. The ADR above, with the second option's friction measured on two or three real commands (`git`, `swift`, `gh`) before it is dismissed.
2. The scrub in the one place a tool process is started (the bash tool and the jobs it runs; the job watchdog already launches with its own `PATH`), covering `wait`-able background jobs too.
3. `Scripts/probe-bash-environment.py` goes from red to green, and is run in `Scripts/quality.sh`'s probe list if there is one.
4. A unit test that the scrub removes each named variable and keeps the ordinary ones, with a fault for each rule.

## Done when

The inheritance probe exits 0: known ask credential variables are withheld, an unknown stand-in is inherited by default and withheld when configured, `HOME` remains, and an explicit
pass-through reaches the command. The stronger requirement that no tool result can contain the starting key remains open until parent-process inspection is addressed.

## Implemented, not yet landed (ADR-0106)

The launch path uses a filtered custom environment for ordinary and sandboxed jobs. Names come from actual authentication readers, presets, provider key references, and MCP
header/environment references. `environment.pass` / `environment.withhold` configure exact exceptions and additional withholding; projects cannot pass credentials through.
The fake-provider probe is green. See diary 2026-10-25-20 for mutations and validation.

## Parent-environment read: closed (ADR-0113)

A sandboxed command recovered the key from ask's own process with `sysctl(KERN_PROCARGS2)`. Seatbelt cannot deny that call and `unsetenv` does not remove the
secret; ask now takes a launch snapshot and overwrites the values of the variables it withholds, in its own environment, once it has read them.
`Scripts/probe-bash-parent-environment.py` is green in the default sandbox and with `--read workspace`; skipping the call, and a blanking that writes nothing, each turn it red.

## Not claimed

That ask can find a secret it does not know about. A key in `AWS_SECRET_ACCESS_KEY` is a person's to withhold, and the entry says so in the configuration help.
