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
        .package(url: "https://github.com/g-cqd/TerminalKit.git", revision: "3079667e77eab559cb40c6ee72a350060ba59a20"),
        .package(url: "https://github.com/g-cqd/AemiJSON.git", revision: "b6aaf0127cc480b33090dc4564324b7abfdcb408"),
        .package(
            url: "https://github.com/g-cqd/AemiMCP.git",
            revision: "992b1a62ec80a85f814bb6f9f7d378ad820d0bcd",
            traits: []
        ),
        .package(url: "https://github.com/g-cqd/AemiRegex.git", revision: "cdde55a04a7fa09afdcd98f9be922402b0583b69"),
        .package(
            url: "https://github.com/g-cqd/AemiMarkdown.git",
            revision: "eccfa4ba6c9a449fc8a062235204530fa067ee17"
        ),
        .package(
            url: "https://github.com/g-cqd/AemiMermaid.git",
            revision: "6bce3d23db8b727a5d45d2f3dc07f63e1f1678c9"
        ),
        .package(url: "https://github.com/g-cqd/AemiHMMML.git", revision: "433747ef378e0efa33879595d835ae9c3b8ca81d"),
        .package(url: "https://github.com/g-cqd/AemiHTML.git", revision: "9a5fb3ca87b4355495788de897754737845769ec"),
        .package(url: "https://github.com/g-cqd/AemiSearch.git", revision: "867978ebe89d834edad6b2a407f23c5785177da8"),
        .package(url: "https://github.com/Aemi-Studio/aemi.git", revision: "8633e6352822d15fc11e46b69da6a76adee72f31"),
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
            dependencies: ["AskAI", .product(name: "AemiMCP", package: "AemiMCP")],
            path: "Sources/AskMCP",
            swiftSettings: packageSettings
        ),
        .target(
            name: "AskTools",
            dependencies: [
                "AskAgentCore", "AskAI", "AskCodemode", "AskCore", "AskMCP",
                .product(name: "AemiMCP", package: "AemiMCP"),
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
                "AskAI", "AskAgentCore", "AskApple", "AskCore", "AskGateway", "AskTools", "AskTUI",
                .product(name: "AemiMCP", package: "AemiMCP"),
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
        // ADR-0170: the gateway's channels and protocol, shared by ask's node side and the gateway; Apple's CryptoKit only.
        .target(
            name: "AskGateway",
            dependencies: ["AskCore", .product(name: "AemiJSON", package: "AemiJSON")],
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
                "AskSession", "AskACP", "AskAI", "AskAgentCore", "AskApple", "AskCodemode", "AskCore", "AskGateway",
                "AskTools", "AskTUI", .product(name: "AemiJSON", package: "AemiJSON"),
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
                "AskMCP", "AskAI", .product(name: "AemiMCP", package: "AemiMCP")
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
            name: "AskGatewayTests",
            dependencies: ["AskGateway", "AskCore", .product(name: "AemiJSON", package: "AemiJSON")],
            path: "Tests/AskGatewayTests",
            swiftSettings: packageSettings
        ),
        .testTarget(
            name: "AskSessionTests",
            dependencies: [
                "AskSession", "AskAgentCore", "AskAI", "AskGateway", "AskTools", "AskTUI",
                .product(name: "TerminalKitIO", package: "TerminalKit"),
                .product(name: "AemiSearch", package: "AemiSearch")
            ],
            path: "Tests/AskSessionTests",
            swiftSettings: packageSettings
        ),
        .testTarget(
            name: "AskToolsTests",
            dependencies: [
                "AskTools", "AskAgentCore", "AskAI", "AskCodemode", "AskMCP",
                .product(name: "AemiMCP", package: "AemiMCP"),
                .product(name: "AemiTesting", package: "aemi"), .product(name: "AemiRegex", package: "aemiregex"),
                .product(name: "AemiJSON", package: "AemiJSON"), .product(name: "AemiJSONRPC", package: "AemiJSON")
            ],
            path: "Tests/AskToolsTests",
            swiftSettings: packageSettings
        ),
        .testTarget(
            name: "AskTUITests",
            dependencies: [
                "AskTUI", "AskCore", "AskGateway", .product(name: "AemiLexers", package: "aemi"),
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
