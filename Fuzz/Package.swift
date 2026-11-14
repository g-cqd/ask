// swift-tools-version: 6.4
// Coverage-guided fuzzing of the parsers that read bytes ask did not write (roadmap 0232): a provider's stream, a session file, an MCP
// server's messages, the terminal's input, text from outside. One libFuzzer executable, its target chosen by `ASK_FUZZ_TARGET`;
// `Scripts/fuzz.sh` builds and runs it. Apart from ask's own package, so ask ships none of it and its build links no fuzzer.
import PackageDescription

let package = Package(
    name: "fuzz",
    platforms: [.macOS(.v26)],
    dependencies: [
        .package(name: "ask", path: ".."),
        // The same revisions ask pins: one revision of a package in a graph.
        .package(url: "https://github.com/g-cqd/AemiJSON.git", revision: "806b481d8cc7e21f07d45537b625c5ac9abfc87e"),
        .package(url: "https://github.com/g-cqd/AemiSearch.git", revision: "3894f0cd180529b82ddb190e50b5b52e7092f4c0"),
        .package(url: "https://github.com/g-cqd/TerminalKit.git", revision: "7913fe66c32d9d715de37f3051c5427ff92f6247")
    ],
    targets: [
        .executableTarget(
            name: "ask-fuzz",
            dependencies: [
                .product(name: "AskAI", package: "ask"), .product(name: "AskAgentCore", package: "ask"),
                .product(name: "AskMCP", package: "ask"), .product(name: "AskTools", package: "ask"),
                .product(name: "AemiJSON", package: "AemiJSON"), .product(name: "AemiSearch", package: "AemiSearch"),
                .product(name: "TerminalKitInput", package: "TerminalKit")
            ],
            path: "Sources/ask-fuzz",
            // libFuzzer brings `main`. ask's own modules are instrumented when `ASK_FUZZ` is set (its manifest), which
            // `Scripts/fuzz.sh` does; AemiJSON, AemiSearch and TerminalKit are not, so their code gives the fuzzer no guidance.
            swiftSettings: [.unsafeFlags(["-parse-as-library", "-sanitize=fuzzer"])],
            // At the link too: it brings libFuzzer's runtime and its `main`.
            linkerSettings: [.unsafeFlags(["-sanitize=fuzzer"])]
        )
    ]
)
