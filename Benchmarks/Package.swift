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
        .package(url: "https://github.com/ordo-one/package-benchmark", .upToNextMajor(from: "1.38.0"))
    ],
    targets: [
        .executableTarget(
            name: "SessionFileBenchmarks",
            dependencies: [
                .product(name: "Benchmark", package: "package-benchmark"),
                .product(name: "AskAgentCore", package: "ask")
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
        )
    ]
)
