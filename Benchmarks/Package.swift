// swift-tools-version: 6.4
import PackageDescription

// ask's benchmarks (ADR-0016), on ordo-one's package-benchmark. A separate package, so the shipping build
// never resolves the framework, and it depends on the parent by path, so it measures the working tree —
// the before and after of the change being made, not whatever was last pushed.
//
// Run: cd Benchmarks && BENCHMARK_DISABLE_JEMALLOC=1 swift package benchmark
// jemalloc (malloc metrics) does not build on macOS 27 yet; allocation counts come from tests instead.
let package = Package(
    name: "benchmarks",
    platforms: [.macOS(.v26)],
    dependencies: [
        .package(name: "ask", path: ".."),
        .package(url: "https://github.com/ordo-one/package-benchmark", .upToNextMajor(from: "1.38.0")),
        // The same revision ask pins; SwiftPM resolves one revision per package.
        .package(url: "https://github.com/g-cqd/TerminalKit.git", revision: "8190500d29d581b99ec5271ec59e014d6fff3045"),
        // The same revision ask pins, for MCPStress's codec floor.
        .package(url: "https://github.com/g-cqd/AemiJSON.git", revision: "5542d37ff0edb17c822b48fe69bff6e792354c57")
    ],
    targets: [
        .executableTarget(
            name: "SessionFileBenchmarks",
            dependencies: [
                .product(name: "Benchmark", package: "package-benchmark"),
                .product(name: "AskAgentCore", package: "ask"),
                .product(name: "AskTools", package: "ask")
            ],
            path: "Benchmarks/SessionFileBenchmarks",
            plugins: [.plugin(name: "BenchmarkPlugin", package: "package-benchmark")]
        ),
        .executableTarget(
            name: "StreamBenchmarks",
            dependencies: [
                .product(name: "Benchmark", package: "package-benchmark"),
                .product(name: "AskAI", package: "ask")
            ],
            path: "Benchmarks/StreamBenchmarks",
            plugins: [.plugin(name: "BenchmarkPlugin", package: "package-benchmark")]
        ),
        .executableTarget(
            name: "RenderBenchmarks",
            dependencies: [
                .product(name: "Benchmark", package: "package-benchmark"),
                .product(name: "AskTUI", package: "ask"),
                .product(name: "TerminalKitCodecs", package: "TerminalKit"),
                .product(name: "TerminalKitInput", package: "TerminalKit"),
                .product(name: "TerminalKitRender", package: "TerminalKit"),
                .product(name: "TerminalKitStyle", package: "TerminalKit"),
                .product(name: "TerminalKitText", package: "TerminalKit"),
                .product(name: "TerminalKitIO", package: "TerminalKit")
            ],
            path: "Benchmarks/RenderBenchmarks",
            plugins: [.plugin(name: "BenchmarkPlugin", package: "package-benchmark")]
        ),
        // Measures the real RenderPipeline, which is main-actor isolated: top-level code runs on the main actor,
        // which the benchmark framework's closures cannot.
        .executableTarget(
            name: "PipelineProbe",
            dependencies: [
                .product(name: "AskTUI", package: "ask"),
                .product(name: "TerminalKitRender", package: "TerminalKit"),
                .product(name: "TerminalKitIO", package: "TerminalKit")
            ],
            path: "Benchmarks/PipelineProbe"
        ),
        // MCP calls under stress (roadmap 0114): a plain executable, because its stdio and HTTP cases run child processes and compare each
        // layer with the floor beneath it. Run: swift run -c release MCPStress [calls]
        .executableTarget(
            name: "MCPStress",
            dependencies: [
                .product(name: "AskMCP", package: "ask"),
                .product(name: "AskAI", package: "ask"),
                .product(name: "AemiJSON", package: "AemiJSON")
            ],
            path: "Benchmarks/MCPStress"
        )
    ]
)
