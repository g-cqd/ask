internal import Foundation

/// Reads the repository's own Swift sources so the standards can be checked rather than remembered.
///
/// This is deliberately a **source scan** and not a compiler setting. `@unchecked Sendable` is
/// syntactically legal and only wrong when unaccompanied by a justification; no compiler flag can see
/// that, so the check has to read the text.
///
/// The scan walks outward from this file to the repository root, the same way ``DocumentationLayout``
/// finds `docs/`, so it works from any checkout without configuration.
enum SourceStandards {
    /// Repository root, found by walking up to the directory holding `Package.swift`.
    static let repositoryRoot: URL = {
        var directory = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()  // AskCoreTests
            .deletingLastPathComponent()  // Tests
            .deletingLastPathComponent()  // repository root
        return directory
    }()

    /// The guard's own files, which are excluded from every scan.
    ///
    /// A linter has to name every construct it bans, so without this it fails on itself on the first
    /// run. That is the rule "a guard must be probed by breaking it" taken one step further: the guard
    /// is the *definition* of the rules, so it is not itself subject to them.
    private static let excludedPrefix = "SourceStandards"

    /// Every `.swift` file under `Sources`, in path order.
    static var sources: [URL] {
        swiftFiles(in: repositoryRoot.appending(path: "Sources")).filter { !isGuard($0) }
    }

    /// Every `.swift` file under `Tests`, in path order.
    static var tests: [URL] {
        swiftFiles(in: repositoryRoot.appending(path: "Tests")).filter { !isGuard($0) }
    }

    private static func isGuard(_ url: URL) -> Bool {
        url.deletingPathExtension().lastPathComponent.hasPrefix(excludedPrefix)
    }

    /// `path:line` for every occurrence of `needle`, skipping lines where it appears inside a comment.
    ///
    /// Comment lines are skipped because a file that *documents* a banned construct must not fail its
    /// own repository's gate — which is exactly the situation this file is in.
    static func occurrences(of needle: String, in files: [URL]) throws -> [String] {
        var found: [String] = []
        for file in files {
            let text = try String(contentsOf: file, encoding: .utf8)
            for (index, line) in text.split(separator: "\n", omittingEmptySubsequences: false).enumerated()
            where line.contains(needle) && !isComment(line) {
                found.append("\(relative(file)):\(index + 1)")
            }
        }
        return found
    }

    /// `@unchecked Sendable` declarations with no `SAFETY:` justification in the comment block above.
    ///
    /// - Returns: `path:line` for each unannotated declaration.
    static func uncheckedSendableWithoutSafetyComment() throws -> [String] {
        var found: [String] = []
        for file in sources + tests {
            let lines = try String(contentsOf: file, encoding: .utf8)
                .split(separator: "\n", omittingEmptySubsequences: false)
            for (index, line) in lines.enumerated() where line.contains("@unchecked Sendable") {
                if !hasSafetyComment(lines, at: index) { found.append("\(relative(file)):\(index + 1)") }
            }
        }
        return found
    }

    /// Whether the comment block immediately above `index` carries a `SAFETY:` justification.
    ///
    /// The search walks upward through contiguous comment lines, so a `SAFETY:` note separated from
    /// its declaration by a doc comment still counts. Requiring it on the immediately preceding line
    /// would have rejected `POSIXTerminalConnection`, which states its invariant and then documents
    /// itself — the note is there, and demanding one arrangement enforces formatting, not safety.
    private static func hasSafetyComment(_ lines: [Substring], at index: Int) -> Bool {
        if lines[index].contains("SAFETY:") { return true }
        var cursor = index - 1
        while cursor >= 0, isComment(lines[cursor]) {
            if lines[cursor].contains("SAFETY:") { return true }
            cursor -= 1
        }
        return false
    }

    /// `Task.sleep` inside a test, skipping the ones that name an injected clock.
    ///
    /// `AsyncEventProbe.wait(forAtLeast:within:clock:)` is the sanctioned form: it parks on a
    /// `TestClock` and ends when the event arrives, so a test using it contains no real-time deadline.
    static func testSleeps() throws -> [String] {
        var found: [String] = []
        for file in tests {
            let lines = try String(contentsOf: file, encoding: .utf8)
                .split(separator: "\n", omittingEmptySubsequences: false)
            for (index, line) in lines.enumerated()
            where line.contains("Task.sleep") && !line.contains("clock:") && !isComment(line) {
                found.append("\(relative(file)):\(index + 1)")
            }
        }
        return found
    }

    // MARK: - Files

    private static func swiftFiles(in directory: URL) -> [URL] {
        guard
            let enumerator = FileManager.default.enumerator(
                at: directory,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            )
        else { return [] }
        return enumerator.compactMap { $0 as? URL }
            .filter { $0.pathExtension == "swift" }
            .sorted { $0.path < $1.path }
    }

    private static func relative(_ url: URL) -> String {
        url.path.replacingOccurrences(of: repositoryRoot.path + "/", with: "")
    }

    /// Whether a line is a comment, or continues one.
    private static func isComment(_ line: Substring) -> Bool {
        let trimmed = line.drop(while: { $0 == " " || $0 == "\t" })
        return trimmed.hasPrefix("//") || trimmed.hasPrefix("*") || trimmed.hasPrefix("/*")
    }
}
