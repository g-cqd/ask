import Foundation
import Testing

/// SwiftPM cannot resolve two revision requirements for one package in the same graph.
@Suite("Benchmarks measure the shipping dependency graph")
struct BenchmarkDependencyTests {
    @Test func `the benchmark and shipping manifests pin the same terminal stack`() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent()
        let pins = try ["Package.swift", "Benchmarks/Package.swift"]
            .map { path in
                let text = try String(contentsOf: root.appending(path: path), encoding: .utf8)
                let match = try #require(
                    text.firstMatch(
                        of:
                            #/\.package\(url: "https://github\.com/g-cqd/TerminalKit\.git", revision: "([a-f0-9]{40})"\)/#
                    ))
                return String(match.1)
            }
        #expect(
            pins[0] == pins[1], "A dependency update must update both manifests; otherwise benchmarks cannot resolve.")
    }
}
