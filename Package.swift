// swift-tools-version: 6.4
import PackageDescription

// ask — a Swift coding agent.
//
// ONE package, MANY small targets, so a given binary links only what it uses. The kernel tier
// (byte/number/Unicode/text/IO/concurrency) and the deterministic test kit come from Aemi; the
// terminal stack comes from the shared AemiTerminal package. `ask` layers the agent on top.
//
// Layout of the targets as they land:
//   AskCore        — perf budgets, session identity, errors. No I/O.
//   AskTerminal    — thin bindings over AemiTerminal (capability negotiation, reset ladder).
//   AskTUI         — screen model, widgets, input routing.
//   AskAgent       — agent loop, tool execution, session persistence.
//   AskProviders   — model providers and streaming.
//   AskCodeMode    — the Swift/Python/Bash/JavaScript codemode host.
//
// AemiRuntime (kernel pools/seams) and any app-level concurrency provider are deliberately never
// co-exported from a single umbrella target, matching the Aemi rule.

// The strictest settings a Swift package can carry, applied to every target here.
//
//   `.v6`                     — complete strict-concurrency checking; every sendable crossing is checked.
//   `StrictMemorySafety`      — SE-0458. The terminal stack moves bytes through raw pointers and
//                               POSIX descriptors, which is exactly where an unchecked access is
//                               a silent memory-corruption bug. The check is the point.
//   `ExistentialAny`          — every existential spells out `any`, so a protocol's intent is legible.
//   `InternalImportsByDefault`— a module sees only what it declares.
//   `MemberImportVisibility`  — a member is only visible when its module is imported.
//   `InferIsolatedConformances` — no unannotated conformance silently guesses its isolation.
//   `treatAllWarnings(as: .error)` — a warning is a defect with a louder voice.
//
// Already implied by `.swiftLanguageMode(.v6)`, and therefore deliberately NOT listed here, because
// the compiler rejects a redundant flag: `RegionBasedIsolation`, `DisableOutwardActorInference`,
// `InferSendableFromCaptures`, `DeprecateApplicationMain`. Naming them would be noise; `.v6` is
// what actually turns them on, and it is the only way to guarantee they stay on.
//
// The expression type-check threshold below diagnoses slow compilation, not runtime latency.
// It does not prevent @testable imports when testability is explicitly enabled (ADR-0006).
// Runtime performance claims still require measurement of the separate shipping release build.
//
// SAFETY: `-Ounchecked` is deliberately NOT used. It would strip the bounds and overflow checks
// that `StrictMemorySafety` relies on, trading correctness for a benchmark number. Performance in
// `ask` comes from doing less work (diff rendering, pooled buffers), not from removing the checks
// that catch the bugs.
let strictSettings: [SwiftSetting] = [
    .swiftLanguageMode(.v6),
    .enableUpcomingFeature("StrictMemorySafety"),
    .enableUpcomingFeature("ExistentialAny"),
    .enableUpcomingFeature("InferIsolatedConformances"),
    .enableUpcomingFeature("InternalImportsByDefault"),
    .enableUpcomingFeature("MemberImportVisibility"),
    .treatAllWarnings(as: .error),
    .unsafeFlags(["-Xfrontend", "-warn-long-expression-type-checking=500"])
]

/// Settings for every target in this package. `swift build` and `swift test` always run release
/// configuration: the package ships a terminal agent whose entire reason to exist is latency, and a
/// debug build measures a program nobody runs.
let packageSettings: [SwiftSetting] = strictSettings

let package = Package(
    name: "ask",
    platforms: [.macOS(.v26)],
    products: [
        .executable(name: "ask", targets: ["ask"]),
        .library(name: "AskCore", targets: ["AskCore"]),
        .library(name: "AskTUI", targets: ["AskTUI"])
    ],
    dependencies: [
        // The terminal stack. TerminalKit is the whole point of the extraction: `ask` links the same
        // terminal code Atelier's KittyCode does, rather than a third copy of it.
        .package(url: "https://github.com/g-cqd/TerminalKit.git", branch: "main")
    ],
    targets: [
        .target(
            name: "AskCore",
            path: "Sources/AskCore",
            swiftSettings: packageSettings
        ),
        .target(
            name: "AskTUI",
            dependencies: [
                .product(name: "TerminalKitCore", package: "TerminalKit"),
                .product(name: "TerminalKitCodecs", package: "TerminalKit"),
                .product(name: "TerminalKitIO", package: "TerminalKit")
            ],
            path: "Sources/AskTUI",
            swiftSettings: packageSettings
        ),
        .executableTarget(
            name: "ask",
            dependencies: ["AskCore", "AskTUI"],
            path: "Sources/ask",
            swiftSettings: packageSettings
        ),
        .testTarget(
            name: "AskCoreTests",
            dependencies: ["AskCore"],
            path: "Tests/AskCoreTests",
            swiftSettings: packageSettings
        )
    ]
)
