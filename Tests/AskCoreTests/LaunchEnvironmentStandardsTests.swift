internal import Foundation
internal import Testing

@testable import AskCore

/// ask blanks the credentials it has read from its own process (ADR-0113), so what the executable reads afterwards must come from the snapshot taken at
/// launch. `Sources/ask` has no tests, so the rule is a source scan: a read of the live environment there would work until the day it needed a blanked value.
@Suite("The executable reads the launch environment, never its own blanked copy")
struct LaunchEnvironmentStandardsTests {
    /// The library calls whose default reads the live environment.
    private static let defaulted = ["SessionDirectory(", "CredentialFile.standard("]

    /// Lines of `text`, 1-based, where a call to one of `callees` does not name `environment:` among its arguments.
    ///
    /// A call is read from its opening parenthesis to the matching one, so a call that swift-format wrapped over several lines is one call. Comment lines are skipped.
    static func callsWithoutEnvironment(in text: String, callees: [String] = defaulted) -> [Int] {
        let code = text.split(separator: "\n", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces).hasPrefix("//") ? "" : String($0) }
            .joined(separator: "\n")
        var found: [Int] = []
        for callee in callees {
            var from = code.startIndex
            while let hit = code.range(of: callee, range: from ..< code.endIndex) {
                from = hit.upperBound
                var depth = 1
                var end = hit.upperBound
                while end < code.endIndex, depth > 0 {
                    if code[end] == "(" { depth += 1 } else if code[end] == ")" { depth -= 1 }
                    end = code.index(after: end)
                }
                if !code[hit.upperBound ..< end].contains("environment:") {
                    found.append(code[..<hit.lowerBound].filter { $0 == "\n" }.count + 1)
                }
            }
        }
        return found.sorted()
    }

    private func files(in directory: String) throws -> [(name: String, text: String)] {
        let root = SourceStandards.repositoryRoot.appending(path: directory)
        return try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "swift" }
            .map { ($0.lastPathComponent, try String(contentsOf: $0, encoding: .utf8)) }
    }

    @Test func `nothing in the executable reads the process's own environment`() throws {
        let offenders = try files(in: "Sources/ask")
            .flatMap { file in
                file.text.split(separator: "\n", omittingEmptySubsequences: false).enumerated()
                    .filter { !$0.element.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
                    .filter {
                        $0.element.contains("ProcessInfo.processInfo.environment") || $0.element.contains("getenv(")
                    }
                    .map { "\(file.name):\($0.offset + 1)" }
            }
        #expect(offenders.isEmpty, "read `LaunchEnvironment.values`: \(offenders)")
    }

    @Test func `a library call whose default is the live environment is given the launch one`() throws {
        let offenders = try files(in: "Sources/ask")
            .flatMap { file in
                Self.callsWithoutEnvironment(in: file.text).map { "\(file.name):\($0)" }
            }
        #expect(offenders.isEmpty, "pass `environment: LaunchEnvironment.values`: \(offenders)")
    }

    @Test func `the scan reads a call that was wrapped over several lines as one call`() {
        let wrappedMissing = "let a = 1\nlet d = SessionDirectory(\n    project: p,\n    home: h)\n"
        let wrappedGiven = "let d = SessionDirectory(\n    project: p,\n    environment: LaunchEnvironment.values)\n"
        let nested = "let d = SessionDirectory(project: f(x), environment: LaunchEnvironment.values)\n"
        #expect(Self.callsWithoutEnvironment(in: wrappedMissing) == [2])
        #expect(Self.callsWithoutEnvironment(in: wrappedGiven).isEmpty)
        #expect(Self.callsWithoutEnvironment(in: nested).isEmpty)
    }

    @Test func `the scan finds each missing call, in either callee, and skips comments`() {
        let text =
            "// SessionDirectory(project: p)\nlet a = CredentialFile.standard()\nlet b = SessionDirectory(project: p)\n"
        #expect(Self.callsWithoutEnvironment(in: text) == [2, 3])
        #expect(Self.callsWithoutEnvironment(in: "let a = CredentialFile.standard(home: h)\n") == [1])
    }
}
