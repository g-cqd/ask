---
status: in-progress
blocked-by: []
date: 2026-10-26
---

# 0073 — Can ask chat with Xcode's own code model?

Xcode ships a programming-focused on-device model ("CodeLM"). The owner asked whether private APIs let ask hold a chat with it. Findings so far are in `docs/research/xcode-codelm-2026-10.md`; the short version is **not from an ordinary process, on this machine, with SIP on**.

## What is known (probed)

- The model is real, installed and named: bundles `com.apple.fm.code.generate_{small,large}_v{1,2,3}.base` plus a code safety guardrail and `com.apple.gm.safety_deny.{input,output}.code_intelligence`, delivered as the asset set `com.apple.MobileAsset.UAF.FM.CodeLM`.
- It is reached through private Swift frameworks (`TokenGeneration`, `GenerativeModels`, `ModelCatalog`) by `IDELanguageModelKit.IDEModelAccess.tokenGenerator(_:useCaseIdentifier:)`, with locations `onDeviceCodeLM`, `…Small`, `…Large`.
- Xcode holds `com.apple.modelmanager.inference` and `com.apple.modelcatalog.full-access`. An ad-hoc signed binary that claims `com.apple.modelmanager.inference` is **killed by AMFI** (SIGKILL), so the entitlement is enforced; SIP is enabled here.
- The public `FoundationModels` API in the macOS 27 SDK offers use cases `general` and `contentTagging` and variants `core3`, `coreAdvanced3`: no code model.

## Paths, in the order worth trying

1. **Through Xcode, which is entitled.** Find a surface Xcode already exposes that is not its UI: `xcrun mcpbridge` (Xcode's MCP server), the `IDEIntelligenceChat` XPC services (`com.apple.dt.ExternalModelService`), or the agent client protocol (`IDEIntelligenceACP`). Probe which of them can take a prompt for the on-device model. Unprobed.
2. **Public API only**: check whether `SystemLanguageModel` in macOS 27 can be pointed at the code bundles through a use-case identifier a third party may set. The use case type is a closed set in the interface; not probed at runtime.
3. **Private symbols directly** (Abysm for the Objective-C-visible wrappers in `ModelCatalog`; the Swift types have only `.tbd` stubs, no interface): possible only in a process allowed the entitlement, so it needs SIP/AMFI off. Not a thing to ship, and not acceptable as a default.

## Done when

Either a probe shows a supported way to send a prompt to the code model and read the answer (then a provider like `AskApple`'s, named `xcode`, with its budget and tests), or the findings say, with probes, that there is none and this entry closes as won't-do. Nothing private is linked into ask in the meantime.
