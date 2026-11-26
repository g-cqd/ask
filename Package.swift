// swift-tools-version: 6.4
import PackageDescription

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

let fuzzSettings: [SwiftSetting] =
    Context.environment["ASK_FUZZ"] == nil ? [] : [.unsafeFlags(["-sanitize=fuzzer", "-enable-testing"])]

let packageSettings: [SwiftSetting] = strictSettings + fuzzSettings

let package = Package(
    name: "ask",
    platforms: [.macOS(.v26)],
    products: [
        .executable(name: "ask", targets: ["ask"]),
        .library(name: "AskAgentCore", targets: ["AskAgentCore"]),
        .library(name: "AskAI", targets: ["AskAI"]),
        .library(name: "AskMCP", targets: ["AskMCP"]),
        .library(name: "AskTools", targets: ["AskTools"]),
        .library(name: "AskTUI", targets: ["AskTUI"])
    ],
    dependencies: [
        .package(url: "https://github.com/g-cqd/TerminalKit.git", revision: "a777029a43269692cac6485c254ff0c1b438789e"),
        .package(url: "https://github.com/g-cqd/AemiJSON.git", revision: "75deac170071149540c436bdab47a5c6d5520a4a"),
        .package(url: "https://github.com/g-cqd/AemiRegex.git", revision: "792eebdcdf3a47daf8ba6ae9a1dfd4c6c5833fc4"),
        .package(
            url: "https://github.com/g-cqd/AemiMarkdown.git",
            revision: "2240dc9329db6a6770cc60ecf5b14084282c17df"
        ),
        .package(
            url: "https://github.com/g-cqd/AemiMermaid.git",
            revision: "14bc98fdf9e9e29cc14c0dc4a319688bd25d1b27"
        ),
        .package(url: "https://github.com/g-cqd/AemiHMMML.git", revision: "dd439204570a9969612ea009608ec39e455c6a33"),
        .package(url: "https://github.com/g-cqd/AemiHTML.git", revision: "0b817d306a4c48f0818b353acbfd83175289843c"),
        .package(url: "https://github.com/g-cqd/AemiSearch.git", revision: "7fb8acb14e93af22211a6bd025d56b72f1496a5d"),
        .package(url: "https://github.com/Aemi-Studio/aemi.git", revision: "1567137e2c810eb489facf29d90a2c623b75d604"),
        .package(url: "https://github.com/swiftlang/swift-subprocess.git", .upToNextMinor(from: "1.0.2")),
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
                "AskCore",
                .product(name: "AemiRegex", package: "aemiregex"),
                .product(name: "AemiText", package: "aemi"), .product(name: "AemiDiff", package: "aemi"),
                .product(name: "AemiArgon2", package: "aemi"),
                .product(name: "AemiSearch", package: "AemiSearch"),
                .product(name: "AemiFrontMatter", package: "AemiHMMML"),
                .product(name: "AemiHMMMLCore", package: "AemiHMMML"),
                .product(name: "AemiTOML", package: "AemiHMMML"),
                .product(name: "AemiYAML", package: "AemiHMMML")
            ],
            path: "Sources/AskAgentCore",
            swiftSettings: packageSettings
        ),
        .target(
            name: "AskAI",
            dependencies: [
                "AskCore", .product(name: "AemiJSON", package: "AemiJSON"),
                .product(name: "AemiRegex", package: "aemiregex")
            ],
            path: "Sources/AskAI",
            swiftSettings: packageSettings
        ),
        .target(
            name: "AskApple",
            dependencies: ["AskAI", "AskAgentCore", .product(name: "AemiJSON", package: "AemiJSON")],
            path: "Sources/AskApple",
            swiftSettings: packageSettings
        ),
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
                "AskAgentCore", "AskAI", "AskCodemode", "AskCore", "AskMCP",
                .product(name: "AemiKernel", package: "aemi"),
                .product(name: "AemiJSON", package: "AemiJSON"),
                .product(name: "AemiJSONRPC", package: "AemiJSON"), .product(name: "AemiSearch", package: "AemiSearch"),
                .product(name: "AemiHTML", package: "AemiHTML"),
                .product(name: "AemiIO", package: "aemi"), .product(name: "Subprocess", package: "swift-subprocess")
            ],
            path: "Sources/AskTools",
            swiftSettings: packageSettings
        ),
        .target(
            name: "AskTUI",
            dependencies: [
                "AskCore",
                .product(name: "TerminalKitCodecs", package: "TerminalKit"),
                .product(name: "TerminalKitIO", package: "TerminalKit"),
                .product(name: "TerminalKitInput", package: "TerminalKit"),
                .product(name: "TerminalKitRender", package: "TerminalKit"),
                .product(name: "TerminalKitStyle", package: "TerminalKit"),
                .product(name: "TerminalKitText", package: "TerminalKit"),
                .product(name: "TerminalKitMarkdown", package: "TerminalKit"),
                .product(name: "AemiMarkdown", package: "AemiMarkdown"),
                .product(name: "AemiMermaidSyntax", package: "AemiMermaid"),
                .product(name: "AemiMermaidScene", package: "AemiMermaid"),
                .product(name: "AemiMermaidLayout", package: "AemiMermaid"),
                .product(name: "AemiMermaidText", package: "AemiMermaid"),
                .product(name: "AemiRegex", package: "aemiregex"),
                .product(name: "AemiJSON", package: "AemiJSON"),
                .product(name: "AemiLexers", package: "aemi")
            ],
            path: "Sources/AskTUI",
            swiftSettings: packageSettings
        ),
        .target(
            name: "AskSession",
            dependencies: [
                .product(name: "AemiSearch", package: "AemiSearch"),
                "AskAI", "AskAgentCore", "AskApple", "AskCore", "AskMCP", "AskTools", "AskTUI",
                .product(name: "AemiJSON", package: "AemiJSON"),
                .product(name: "TerminalKitInput", package: "TerminalKit")
            ],
            swiftSettings: packageSettings
        ),
        .target(
            name: "AskCodemode",
            dependencies: [
                .product(name: "AemiJSON", package: "AemiJSON"), .product(name: "AemiJSONRPC", package: "AemiJSON"),
                .product(name: "AemiRuntime", package: "aemi")
            ],
            swiftSettings: packageSettings
        ),
        .target(
            name: "AskACP",
            dependencies: [
                "AskTUI",
                .product(name: "AemiJSON", package: "AemiJSON"), .product(name: "AemiJSONRPC", package: "AemiJSON"),
                .product(name: "AemiRuntime", package: "aemi")
            ],
            swiftSettings: packageSettings
        ),
        .executableTarget(
            name: "ask",
            dependencies: [
                "AskSession", "AskACP", "AskAI", "AskAgentCore", "AskApple", "AskCodemode", "AskCore", "AskTools",
                "AskTUI",
                .product(name: "ArgumentParser", package: "swift-argument-parser")
            ],
            path: "Sources/ask",
            swiftSettings: packageSettings,
            linkerSettings: [
                .unsafeFlags(
                    ["-Xlinker", "-order_file", "-Xlinker", Context.packageDirectory + "/Scripts/ask-startup.order"],
                    .when(configuration: .release)
                )
            ]
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
                "AskAgentCore", "AskAI", "AskCore", .product(name: "AemiIO", package: "aemi"),
                .product(name: "AemiJSON", package: "AemiJSON"), .product(name: "AemiTesting", package: "aemi"),
                .product(name: "AemiSearch", package: "AemiSearch")
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
            dependencies: ["AskAI", "AskCore", .product(name: "AemiJSON", package: "AemiJSON")],
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
            name: "AskCodemodeTests",
            dependencies: [
                "AskCodemode", .product(name: "AemiJSON", package: "AemiJSON"),
                .product(name: "AemiJSONRPC", package: "AemiJSON")
            ],
            path: "Tests/AskCodemodeTests",
            swiftSettings: packageSettings
        ),
        .testTarget(
            name: "AskACPTests",
            dependencies: [
                "AskACP", "AskTUI", .product(name: "AemiJSON", package: "AemiJSON"),
                .product(name: "AemiJSONRPC", package: "AemiJSON")
            ],
            path: "Tests/AskACPTests",
            swiftSettings: packageSettings
        ),
        .testTarget(
            name: "AskSessionTests",
            dependencies: [
                "AskSession", "AskAgentCore", "AskAI", "AskTools", "AskTUI",
                .product(name: "AemiSearch", package: "AemiSearch")
            ],
            path: "Tests/AskSessionTests",
            swiftSettings: packageSettings
        ),
        .testTarget(
            name: "AskToolsTests",
            dependencies: [
                "AskTools", "AskAgentCore", "AskAI", "AskCodemode", "AskMCP",
                .product(name: "AemiTesting", package: "aemi"), .product(name: "AemiRegex", package: "aemiregex"),
                .product(name: "AemiJSON", package: "AemiJSON"), .product(name: "AemiJSONRPC", package: "AemiJSON")
            ],
            path: "Tests/AskToolsTests",
            swiftSettings: packageSettings
        ),
        .testTarget(
            name: "AskTUITests",
            dependencies: [
                "AskTUI", "AskCore", .product(name: "AemiLexers", package: "aemi"),
                .product(name: "TerminalKitIO", package: "TerminalKit"),
                .product(name: "TerminalKitCore", package: "TerminalKit"),
                .product(name: "TerminalKitCodecs", package: "TerminalKit"),
                .product(name: "TerminalKitInput", package: "TerminalKit"),
                .product(name: "TerminalKitRender", package: "TerminalKit"),
                .product(name: "TerminalKitStyle", package: "TerminalKit"),
                .product(name: "TerminalKitText", package: "TerminalKit"),
                .product(name: "TerminalKitMarkdown", package: "TerminalKit"),
                .product(name: "AemiMarkdown", package: "AemiMarkdown")
            ],
            path: "Tests/AskTUITests",
            swiftSettings: packageSettings
        )
    ]
)
