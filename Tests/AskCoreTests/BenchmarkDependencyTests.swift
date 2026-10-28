internal import AemiRegex
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
                return try #require(
                    capture(
                        ##"\.package\(url: "https://github\.com/g-cqd/TerminalKit\.git", revision: "([a-f0-9]{40})"\)"##,
                        in: text))
            }
        #expect(
            pins[0] == pins[1], "A dependency update must update both manifests; otherwise benchmarks cannot resolve.")
    }
}

/// The first capture group of `pattern` in `text`, matched in linear time.
private func capture(_ pattern: String, in text: String) -> String? {
    guard let compiled = try? Pattern(pattern), let match = compiled.firstMatch(in: text),
        let range = match.range(ofGroup: 1, in: text)
    else { return nil }
    return String(text[range])
}
