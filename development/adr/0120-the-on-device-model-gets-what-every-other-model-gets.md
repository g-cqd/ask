---
status: accepted
date: 2026-10-26
supersedes-in-part: "0116 (the withheld tool, the omitted sandbox argument, the fixed instruction share)"
---

# 0120 — The on-device model gets what every other model gets

## Context

ADR-0116 gave Apple's model a reduced view: the composition root withheld `narrow_sandbox`, the schema left out the `sandbox` argument every tool takes, descriptions were cut to a sentence, and the instructions had a fixed fifth of a 4,096-token window. That was sized for the window
of macOS 26. On macOS 27 here the window is **8,192** tokens, and the request the model got was 689 tokens: most of the window was unused while the model lacked tools and instructions the others had.

The owner asked that every local variant be offered, and that those models get the same information and tools as the others.

## Probed: the variants

`SystemLanguageModel.default` on macOS 27.0.1: `variant` = `AFM 3 Core Advanced` (`.coreAdvanced3`), `contextSize` 8192, available. The SDK interface has `Variant.core3` and `.coreAdvanced3`, **and no initializer takes a variant**: `variant` is a read-only property, chosen by the system for the hardware.
`SystemLanguageModel(useCase: .contentTagging)` reports the same variant and window and is a tagger, not a chat model. `PrivateCloudComputeLanguageModel` (new in 27) is available here too, but it is Apple's servers, not local, and it has a quota; it is not offered.
So there is **one local chat model per Mac**; ask names its variant in `/model` and `ask models apple` (`AppleModel.variantName`) instead of offering a second id that could not be selected. If a later SDK adds a way to choose, each variant becomes a model id.

## Decision

1. No tool is withheld: `AppleProvider` offers every tool the loop has, `narrow_sandbox` and the `sandbox` argument included, as every other provider's request does.
2. Descriptions are whole (up to 600 characters each). If the tools then do not fit **half** the window, their descriptions go down to the first sentence; only if they still do not fit are tools dropped from the end.
3. The instructions get everything the conversation's floor (a quarter of the window) leaves after the reply and the tools, never less than a fifth, so the project's instruction files reach the model whenever there is room.
4. Whatever the window could not hold is **said**: a notice for descriptions cut to a sentence, for tools left out (by name), and for instruction blocks cut or left out. The model is never believed to have what it was not given.

## Evidence

- Real binary, `--provider apple`, a `read` task: the request is 2.1k tokens (was 689), answered correctly; no notice, since everything fit.
- `AppleBudgetTests`, `ApplePromptTests` (omitted blocks are counted), `AppleToolSchemaTests` (the sandbox argument changes the schema; a full description keeps every sentence, a brief one the first; brief costs less) pass.
- The live tests still pass (plain answer, a tool call with typed arguments, a 70 KB conversation cut to fit).

## Consequences

- A three-billion-parameter model sees the same tool list as a frontier one; whether it uses `narrow_sandbox` well is not claimed. If it misuses it, that is a finding to record, not a reason to hide the tool.
- On macOS 26 (4,096 tokens) the full set may not fit; the notices say what was dropped.
- Not done: choosing between `core3` and `coreAdvanced3`, and `PrivateCloudComputeLanguageModel` (not local).
