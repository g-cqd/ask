internal import Foundation
internal import Testing

/// Roadmap 0077: patterns run on AemiRegex's linear-time engine, never on Swift Regex, whose matching can backtrack
/// without bound on a provider's or a file's text.
@Suite("Swift Regex is not used; AemiRegex is")
struct NoSwiftRegexTests {
    private static let forbidden = [
        "import RegexBuilder", "try Regex(", "Regex<", ".firstMatch(of:", ".wholeMatch(of:", ".prefixMatch(of:",
        ".matches(of:", ".replacing(/", ".replacing(#/", "(#/"
    ]

    @Test func `no Swift Regex API or literal appears in sources or tests`() throws {
        var root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        while !FileManager.default.fileExists(atPath: root.appending(path: "Package.swift").path) {
            root = root.deletingLastPathComponent()
            try #require(root.path != "/", "could not locate the repository root")
        }
        var offenders: [String] = []
        for directory in ["Sources", "Tests"] {
            let walker = FileManager.default.enumerator(
                at: root.appending(path: directory), includingPropertiesForKeys: nil)
            for case let url as URL in walker ?? FileManager.default.enumerator(atPath: "/")!
            where url.pathExtension == "swift" {
                guard url.lastPathComponent != "NoSwiftRegexTests.swift" else { continue }
                let text = try String(contentsOf: url, encoding: .utf8)
                for (number, line) in text.split(separator: "\n", omittingEmptySubsequences: false).enumerated()
                where !line.trimmingCharacters(in: .whitespaces).hasPrefix("//")
                    && Self.forbidden.contains(where: { line.contains($0) })
                {
                    offenders.append("\(url.lastPathComponent):\(number + 1)")
                }
            }
        }
        #expect(offenders.isEmpty, "Swift Regex found, use AemiRegex: \(offenders)")
    }
}
