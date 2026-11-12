// swift-tools-version: 6.4
// The MCP conformance suite's client side (roadmap 0123, step 1): a client on AskMCP that the official suite
// (`@modelcontextprotocol/conformance`) runs against its test servers. Apart from ask's own package so ask ships none of it.
import PackageDescription

let package = Package(
    name: "conformance",
    platforms: [.macOS(.v26)],
    dependencies: [.package(name: "ask", path: "..")],
    targets: [
        .executableTarget(
            name: "mcp-conformance-client",
            dependencies: [.product(name: "AskMCP", package: "ask"), .product(name: "AskAI", package: "ask")],
            path: "Sources/mcp-conformance-client"
        )
    ]
)
