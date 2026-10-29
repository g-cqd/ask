// swift-tools-version: 6.4
import PackageDescription

// ask — a Swift coding agent.
//
// ONE package, MANY small targets, so a given binary links only what it uses. The kernel tier
// (byte/number/Unicode/text/IO/concurrency) and the deterministic test kit come from Aemi; the
// terminal stack comes from the shared TerminalKit package. `ask` layers the agent on top.
//
// The target graph is ADR-0009's; targets land when they have content, never as empty shells.
//   AskCore        — budgets, documentation layout, source standards.               (exists)
//   AskAgentCore   — session tree and context construction; later the loop.        (exists)
//   AskTUI         — screen model, widgets, input routing, over TerminalKit only.   (exists)
//   AskAI          — providers, streaming, protocol adapters, auth.                 (exists)
//   AskTools       — read, write, edit, bash over swift-subprocess (ADR-0011).      (exists)
//   AskCodeMode    — the codemode host.                                             (0012)
//   ask            — composition root, the only target that sees everything.
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
        // Consumed by the Benchmarks package (ADR-0016).
        .library(name: "AskAgentCore", targets: ["AskAgentCore"]),
        .library(name: "AskAI", targets: ["AskAI"]),
        .library(name: "AskApple", targets: ["AskApple"]),
        .library(name: "AskMCP", targets: ["AskMCP"]),
        .library(name: "AskTools", targets: ["AskTools"]),
        .library(name: "AskTUI", targets: ["AskTUI"])
    ],
    dependencies: [
        // The terminal stack. TerminalKit is the whole point of the extraction: `ask` links the same
        // terminal code Atelier's KittyCode does, rather than a third copy of it.
        .package(url: "https://github.com/g-cqd/TerminalKit.git", revision: "be91ed889aaf95fc58bdbeaa8b81da2df80bdb32"),
        // JSON for every wire format: sessions now, provider streams and tool arguments next (ADR-0015).
        // Pinned by revision like every Aemi-family package; it shares TerminalKit's Aemi pin.
        .package(url: "https://github.com/g-cqd/AemiJSON.git", revision: "5542d37ff0edb17c822b48fe69bff6e792354c57"),
        // Already resolved through AemiJSON; the linear-time engine also recognizes UI heredoc openers.
        .package(url: "https://github.com/g-cqd/AemiRegex.git", revision: "fe9b07f00f7b52d2d210ed4df43bd2b18f4ad674"),
        // The Markdown parser the transcript draws assistant messages with (roadmap 0065); the revision TerminalKitMarkdown pins.
        .package(
            url: "https://github.com/g-cqd/AemiMarkdown.git", revision: "2e75a94af21a4e942e9478d42c788458ac97bc95"),
        // AemiIO's durability profiles for session files (ADR-0017). The same revision TerminalKit and
        // AemiJSON pin, which SwiftPM requires: one revision per package in a graph.
        .package(url: "https://github.com/Aemi-Studio/aemi.git", revision: "f6da05cd0efdf60700e854efb5b6092eae89b8c5"),
        // Child processes for the bash tool (ADR-0011): the official package, added with the first tool that
        // runs one.
        .package(url: "https://github.com/swiftlang/swift-subprocess.git", .upToNextMinor(from: "1.0.2")),
        // Command-line parsing for the `ask` executable only (ADR-0015). Its link cost against the
        // cold-start budget was measured before adoption.
        .package(url: "https://github.com/apple/swift-argument-parser.git", .upToNextMinor(from: "1.8.2"))
    ],
    targets: [
        .target(
            name: "AskCore",
            dependencies: [.product(name: "AemiJSON", package: "AemiJSON")],
            path: "Sources/AskCore",
            swiftSettings: packageSettings
        ),
        .target(
            name: "AskAgentCore",
            dependencies: [
                "AskAI", .product(name: "AemiJSON", package: "AemiJSON"), .product(name: "AemiIO", package: "aemi"),
                .product(name: "AemiText", package: "aemi")
            ],
            path: "Sources/AskAgentCore",
            swiftSettings: packageSettings
        ),
        .target(
            name: "AskAI",
            dependencies: [
                .product(name: "AemiJSON", package: "AemiJSON"), .product(name: "AemiRegex", package: "aemiregex")
            ],
            path: "Sources/AskAI",
            swiftSettings: packageSettings
        ),
        // Apple's on-device model, linked in-process through FoundationModels (ADR-0116). Its own target, so nothing but the
        // executable links the framework and a library's tests do not load it.
        .target(
            name: "AskApple",
            dependencies: ["AskAI", "AskAgentCore", .product(name: "AemiJSON", package: "AemiJSON")],
            path: "Sources/AskApple",
            swiftSettings: packageSettings
        ),
        // The Model Context Protocol client: JSON-RPC over a transport, no policy (ADR-0096). A leaf, like pi's `pi-mcp`.
        .target(
            name: "AskMCP",
            dependencies: [
                "AskAI", .product(name: "AemiJSON", package: "AemiJSON"),
                .product(name: "Subprocess", package: "swift-subprocess")
            ],
            path: "Sources/AskMCP",
            swiftSettings: packageSettings
        ),
        .target(
            name: "AskTools",
            dependencies: [
                "AskAgentCore", "AskAI", "AskMCP", .product(name: "AemiKernel", package: "aemi"),
                .product(name: "Subprocess", package: "swift-subprocess")
            ],
            path: "Sources/AskTools",
            swiftSettings: packageSettings
        ),
        .target(
            name: "AskTUI",
            dependencies: [
                .product(name: "TerminalKitCore", package: "TerminalKit"),
                .product(name: "TerminalKitCodecs", package: "TerminalKit"),
                .product(name: "TerminalKitIO", package: "TerminalKit"),
                .product(name: "TerminalKitInput", package: "TerminalKit"),
                .product(name: "TerminalKitRender", package: "TerminalKit"),
                .product(name: "TerminalKitStyle", package: "TerminalKit"),
                .product(name: "TerminalKitText", package: "TerminalKit"),
                .product(name: "TerminalKitMarkdown", package: "TerminalKit"),
                .product(name: "AemiMarkdown", package: "AemiMarkdown"),
                .product(name: "AemiRegex", package: "aemiregex")
            ],
            path: "Sources/AskTUI",
            swiftSettings: packageSettings
        ),
        .executableTarget(
            name: "ask",
            dependencies: [
                "AskAI", "AskAgentCore", "AskApple", "AskCore", "AskTools", "AskTUI",
                .product(name: "AemiJSON", package: "AemiJSON"),
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
                .product(name: "TerminalKitInput", package: "TerminalKit")
            ],
            path: "Sources/ask",
            swiftSettings: packageSettings
        ),
        .testTarget(
            name: "AskCoreTests",
            dependencies: [
                "AskCore", .product(name: "AemiJSON", package: "AemiJSON"),
                .product(name: "AemiRegex", package: "aemiregex")
            ],
            path: "Tests/AskCoreTests",
            swiftSettings: packageSettings
        ),
        .testTarget(
            name: "AskAgentCoreTests",
            dependencies: [
                "AskAgentCore", "AskAI", .product(name: "AemiIO", package: "aemi")
            ],
            path: "Tests/AskAgentCoreTests",
            swiftSettings: packageSettings
        ),
        .testTarget(
            name: "AskAppleTests",
            dependencies: ["AskApple", "AskAI", "AskAgentCore"],
            path: "Tests/AskAppleTests",
            swiftSettings: packageSettings
        ),
        .testTarget(
            name: "AskAITests",
            dependencies: ["AskAI"],
            path: "Tests/AskAITests",
            swiftSettings: packageSettings
        ),
        .testTarget(
            name: "AskMCPTests",
            dependencies: [
                "AskMCP", "AskAI", .product(name: "AemiJSON", package: "AemiJSON"),
                .product(name: "AemiTesting", package: "aemi"), .product(name: "AemiRegex", package: "aemiregex")
            ],
            path: "Tests/AskMCPTests",
            exclude: ["Fixtures"],
            swiftSettings: packageSettings
        ),
        .testTarget(
            name: "AskToolsTests",
            dependencies: [
                "AskTools", "AskAgentCore", "AskAI", "AskMCP", .product(name: "AemiTesting", package: "aemi"),
                .product(name: "AemiRegex", package: "aemiregex")
            ],
            path: "Tests/AskToolsTests",
            swiftSettings: packageSettings
        ),
        .testTarget(
            name: "AskTUITests",
            dependencies: [
                "AskTUI",
                .product(name: "TerminalKitIO", package: "TerminalKit"),
                .product(name: "TerminalKitCore", package: "TerminalKit"),
                .product(name: "TerminalKitCodecs", package: "TerminalKit"),
                .product(name: "TerminalKitInput", package: "TerminalKit"),
                .product(name: "TerminalKitRender", package: "TerminalKit"),
                .product(name: "TerminalKitStyle", package: "TerminalKit"),
                .product(name: "TerminalKitText", package: "TerminalKit")
            ],
            path: "Tests/AskTUITests",
            swiftSettings: packageSettings
        )
    ]
)
