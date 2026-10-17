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
// The two `-warn-long-*` limits are the niche pair that matter most here: an agent whose whole
// claim is latency has no excuse for a function body or an expression-type-check that runs long.
// Both thresholds raise a warning, and a warning is an error in this package, so an accidental
// quadratic expression type-check fails the build instead of the benchmark.
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
    .unsafeFlags(["-Xfrontend", "-warn-long-function-bodies=100"]),
    .unsafeFlags(["-Xfrontend", "-warn-long-expression-type-checking=500"]),
]

/// Settings for every target in this package. `swift build` and `swift test` always run release
/// configuration: the package ships a terminal agent whose entire reason to exist is latency, and a
/// debug build measures a program nobody runs.
let packageSettings: [SwiftSetting] = strictSettings

let package = Package(
    name: "ask",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "AskCore", targets: ["AskCore"])
    ],
    dependencies: [
        // Aemi arrives with roadmap entry 0002, once `AemiTerminal` exists inside it and Aemi is
        // tagged. Aemi publishes no tags yet, so a version requirement cannot resolve today, and a
        // dependency nothing imports is a liability rather than a foundation.
    ],
    targets: [
        .target(
            name: "AskCore",
            path: "Sources/AskCore",
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