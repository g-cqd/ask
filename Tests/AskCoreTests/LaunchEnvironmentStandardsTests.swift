internal import Foundation
internal import Testing

@testable import AskCore

/// ask blanks the credentials it has read from its own process (ADR-0113), so what the executable reads afterwards must come from the snapshot taken at
/// launch. `Sources/ask` has no tests, so the rule is a source scan: a read of the live environment there would work until the day it needed a blanked value.
@Suite("The executable reads the launch environment, never its own blanked copy")
struct LaunchEnvironmentStandardsTests {
    private func lines(in directory: String) throws -> [(location: String, text: String)] {
        let root = SourceStandards.repositoryRoot.appending(path: directory)
        let files = try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "swift" }
        return try files.flatMap { file in
            try String(contentsOf: file, encoding: .utf8).split(separator: "\n", omittingEmptySubsequences: false)
                .enumerated().filter { !$0.element.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
                .map { ("\(directory)/\(file.lastPathComponent):\($0.offset + 1)", String($0.element)) }
        }
    }

    @Test func `nothing in the executable reads the process's own environment`() throws {
        let offenders = try lines(in: "Sources/ask")
            .filter {
                $0.text.contains("ProcessInfo.processInfo.environment") || $0.text.contains("getenv(")
            }
        #expect(offenders.isEmpty, "read `LaunchEnvironment.values`: \(offenders.map(\.location))")
    }

    @Test func `a library call whose default is the live environment is given the launch one`() throws {
        let defaulted = ["SessionDirectory(project:", "CredentialFile.standard("]
        let offenders = try lines(in: "Sources/ask")
            .filter { line in
                defaulted.contains { line.text.contains($0) } && !line.text.contains("environment:")
            }
        #expect(offenders.isEmpty, "pass `environment: LaunchEnvironment.values`: \(offenders.map(\.location))")
    }
}
