# Xcode's on-device code model, and whether ask can chat with it (2026-10-26)

Machine: macOS 27.0.1, Xcode 27.0 (27A266a), Apple Silicon, SIP enabled. Everything below was run, not recalled; each line says what.

## Where it lives

| Fact | Probe |
|---|---|
| `IDELanguageModelKit.framework` (Xcode/Contents/Frameworks) defines `IDEModelAccess` with `ModelLocation` cases `onDevice(String)`, `remote(String)`, statics `onDeviceCodeLM`, `onDeviceCodeLMSmall`, `onDeviceCodeLMLarge`, `overrideCodeLMModelBundleIdentifier`; `ModelAvailability` `ready/downloading/notInstalled/noConsent/notAvailable/unknown`; `HardwareSizeClassification.forCurrentDevice`; `tokenGenerator(_:useCaseIdentifier:)`, `sessionConfiguration(_:useCaseIdentifier:)`, `modelBundle(_:)`, `codeLMSafetyService(useCaseIdentifier:)`, `startUsingOnDeviceModel`, `isFeatureEnabledAndReady(IDECodeLMFeature)` | `nm -gU … | swift demangle` |
| Bundle identifiers: `com.apple.fm.code.generate_{small,large}_v{1,2,3}.base`, `com.apple.fm.code.generate_safety_guardrail.base`, `com.apple.gm.safety_deny.{input,output}.code_intelligence.base`; asset set `com.apple.MobileAsset.UAF.FM.CodeLM` | `strings` on the framework |
| The assets are installed here: `/System/Library/AssetsV2/com_apple_MobileAsset_UAF_FM_CodeLM` exists (contents not listable, `Operation not permitted`); locker state files name `generate_small_v1.base`, `generate_small_v2.base`, `generate_safety_guardrail.base` and their tokenizers | `ls`, `find` under `AssetsV2/persisted` |
| Inference is in private system frameworks `TokenGeneration`, `TokenGenerationCore`, `TokenGenerationInference` (ObjC: `E5RunnerObjC`, `TGIE5BaseModelObjC`, …), `GenerativeModels`, `ModelCatalog` (ObjC: `MCResourceInformation`, `…UseCaseAvailabilityInfo`, …). The SDK has `.tbd` stubs only | `otool -L`, SDK `PrivateFrameworks/*.tbd` |
| The Swift surface of `TokenGeneration.TokenGenerator`: `init(configuration: SessionConfiguration)`, `complete(prompt:parameters:…)` returning `TokenStream<String>`, with grammars, schemas, tools and tool choice, `countTokens`, `contextSize()`, `prewarm`, `prepare(promptPrefix:)` | demangled `.tbd` symbols |
| Chat to remote partners is separate: `IDEIntelligenceModelService` has `OpenAIChatModelProvider` (ChatGPT, Codex), `builtInClaude` OAuth, `ExternalModelService.xpc` | `nm` |

## What stops an ordinary process

- Xcode's entitlements include `com.apple.modelmanager.inference` and `com.apple.modelcatalog.full-access`; so do the `IDEIntelligenceChat` XPC services.
- **AMFI enforces it.** A copy of a probe binary ad-hoc signed with `com.apple.modelmanager.inference` exits `Killed: 9`; the unsigned one runs. (`/tmp/probe/list2e`.)
- The unentitled probe that `dlopen`s `ModelCatalog` and enumerates its Objective-C classes traps (`SIGTRAP`) before listing anything: the framework refuses an unentitled client, or the class list contains objects that crash a naive walk. Not told apart.
- The Swift API has no interface file, so calling it without Xcode's headers means declaring layouts by hand against mangled symbols: fragile across every OS update, and useless without the entitlement.

## What the public API offers instead

`FoundationModels` (macOS 27 SDK interface, read in full for this): `SystemLanguageModel.UseCase` is `general` or `contentTagging`; `SystemLanguageModel.Variant` is `core3` or `coreAdvanced3`; `contextSize` is back-deployed; `tokenCount(for:)` from 26.4. Nothing names code generation. `AskApple` uses this API (ADR-0116).

## Not probed (the next steps, roadmap 0073)

Whether Xcode exposes the model to another process through a supported surface: `xcrun mcpbridge` tool list, the ACP agent bridge, the `ExternalModelService` XPC protocol. Whether a use-case identifier a third party may supply selects the code bundles in `SystemLanguageModel`. Whether the Swift 6 `abysm`/`InternedStrings` route (Abysm checks Objective-C signatures and cannot call Swift) has any ObjC-visible entry point into `ModelCatalog` beyond the wrappers listed. Abysm and InternedStrings were cloned to read (`g-cqd/Abysm`: typed ObjC runtime interop, no Swift symbol resolution) — they were not needed for the findings above.

## Consequence

Do not link private frameworks into ask, and do not ask anyone to disable SIP. If a supported surface turns up it is a provider; if not, close the roadmap entry.

## Addendum: the public local variants (same day)

`SystemLanguageModel.default.variant` is `AFM 3 Core Advanced` here, window 8192; `Variant.core3` exists in the interface but no public initializer selects a variant, so ask offers the one the system runs (ADR-0120). `PrivateCloudComputeLanguageModel` exists on 27 and is available, but it is a server model with a quota. Neither is the Xcode code model.
