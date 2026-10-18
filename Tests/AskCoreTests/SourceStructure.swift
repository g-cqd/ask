internal import AskCore
internal import Foundation

/// Checks that the source tree is a map of the types the project owns.
///
/// It lives in the test target, not in `AskCore`: `ask` links `AskCore`, and this is only ever run by tests.
/// Measured when it sat in `AskCore`: idle memory 8224 KiB without it, 8304 KiB with it.
///
/// A directory listing is the cheapest way to learn a codebase, and it only works while a file holds what
/// its name says. The first audit found 30 of 70 files declaring several types, some of them five, so the
/// listing hid most of the project's types and a file could grow without anyone seeing a new concept arrive.
/// The rules are a source scan because no compiler setting can say "a file is named for its type":
///
/// - a file declares **at most one** top-level type, private or not, and is named for it;
/// - an extension in a type's file extends that type, unless every member is `fileprivate` or narrower:
///   a helper nothing else can see adds no concept to the listing;
/// - an extension of any other type lives in `Base+Topic.swift`, with extensions of that one base only;
/// - a file with no type, such as free functions, may have any name;
/// - a nested type is free, which is how a type that only one other type uses stays out of the listing.
///
/// Indented lines are never read, so nested declarations are invisible to the scan by construction.
enum SourceStructure {
    /// The most lines a file may have, for sources and tests alike.
    ///
    /// The longest file when this was adopted had 244 lines, so the ceiling blocks growth and not history.
    /// SwiftLint's own `file_length` is wider (300 warning, 500 error) and does not look at `Tests`.
    static let lineCeiling = 250

    /// One top-level declaration the scan found.
    struct Declaration: Sendable, Equatable {
        /// What kind of declaration it is.
        enum Kind: Sendable, Equatable {
            /// A `struct`, `class`, `enum`, `actor` or `protocol`.
            case type
            /// An `extension`.
            case `extension`
        }

        let kind: Kind
        /// The declared name, or for an extension the outermost type it extends. `[T]` reads as `Array`.
        let name: String
        /// One-based line number.
        let line: Int
        /// Whether this is an extension with at least one member and no member wider than `fileprivate`.
        ///
        /// Nothing outside the file can see such an extension, so it adds no concept to the project and
        /// needs no place in the listing. An empty extension is not one: it adds a conformance.
        let isFileLocalHelper: Bool
    }

    /// Built per scan, not stored: `Regex` is not `Sendable`, and a scan reads a file, not a hot path.
    private static func declarationPattern() -> Regex<(Substring, Substring, Substring)> {
        /^(?:(?:public|internal|private|fileprivate|package|open|final|indirect|nonisolated|@\w+(?:\([^)]*\))?)\s+)*(struct|class|enum|actor|protocol|extension)\s+(\[|[A-Za-z_]\w*)/
    }

    /// The top-level declarations in `text`, in order.
    ///
    /// Only lines that start in column zero are read, and neither comments nor the inside of a multi-line
    /// string literal are: a file may document or quote a declaration without being charged for it.
    static func declarations(in text: String) -> [Declaration] {
        let declaration = declarationPattern()
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        var found: [Declaration] = []
        var insideString = false
        for (index, line) in lines.enumerated() {
            let wasInside = insideString
            if (line.components(separatedBy: "\"\"\"").count - 1) % 2 == 1 { insideString.toggle() }
            guard !wasInside, let first = line.first, !first.isWhitespace, !line.hasPrefix("//"),
                let match = line.firstMatch(of: declaration)
            else { continue }
            let isExtension = match.output.1 == "extension"
            let name = match.output.2 == "[" ? "Array" : String(match.output.2)
            found.append(
                Declaration(
                    kind: isExtension ? .extension : .type, name: name, line: index + 1,
                    isFileLocalHelper: isExtension && hasOnlyPrivateMembers(lines[(index + 1)...])))
        }
        return found
    }

    /// Whether the members of the extension that `body` begins, up to its closing brace, are all private.
    ///
    /// Members are the lines indented exactly one level; attribute-only lines and comments are skipped,
    /// and deeper lines are bodies and continuations.
    private static func hasOnlyPrivateMembers(_ body: ArraySlice<Substring>) -> Bool {
        var members = 0
        for line in body {
            if line.hasPrefix("}") { break }
            guard line.hasPrefix("    "), line.dropFirst(4).first.map({ !$0.isWhitespace }) == true else { continue }
            var member = line.dropFirst(4)
            while member.hasPrefix("@") {
                guard let space = member.firstIndex(of: " ") else {
                    member = ""
                    break
                }
                member = member[space...].drop(while: { $0 == " " })
            }
            guard !member.isEmpty, !member.hasPrefix("//"), !member.hasPrefix("}"), !member.hasPrefix(")") else {
                continue
            }
            guard member.hasPrefix("private ") || member.hasPrefix("fileprivate ") else { return false }
            members += 1
        }
        return members > 0
    }

    /// What is wrong with a file of this name and text, one sentence each; empty when it is as it should be.
    static func violations(fileName: String, text: String) -> [String] {
        let all = declarations(in: text)
        let types = all.filter { $0.kind == .type }
        let extensions = all.filter { $0.kind == .extension }
        let stem = fileName.hasSuffix(".swift") ? String(fileName.dropLast(6)) : fileName
        var found: [String] = []

        if types.count > 1 {
            let names = types.map(\.name).joined(separator: ", ")
            found.append("declares \(types.count) types (\(names)); each type gets its own file")
        } else if let only = types.first {
            if only.name != stem { found.append("is named \(stem) but declares \(only.name)") }
            for foreign in extensions where foreign.name != only.name && !foreign.isFileLocalHelper {
                found.append("extends \(foreign.name) beside \(only.name); move it to \(foreign.name)+Topic.swift")
            }
        }
        if types.isEmpty, let first = extensions.first {
            let bases = Set(extensions.map(\.name))
            if bases.count > 1 {
                found.append("extends \(bases.sorted().joined(separator: " and ")); one file per extended type")
            } else if !stem.hasPrefix("\(first.name)+") {
                found.append("extends \(first.name) but is named \(stem); name it \(first.name)+Topic.swift")
            }
        }
        return found
    }

    /// Files that break a structure rule today and are waiting for their split, so the rule can be enforced
    /// everywhere else now.
    ///
    /// Each is being edited by someone else at the time of writing, and splitting it underneath them would
    /// make their work unmergeable. The list is a ratchet: ``staleBaseline(_:)`` fails the build when an entry
    /// is clean, so it can shrink and never grow, and a new violation is never added here, only fixed.
    static let knownViolations: Set<String> = [
        "Sources/AskTUI/AskTUI.swift", "Sources/AskTUI/InteractiveScreen.swift", "Sources/ask/AskMain.swift",
        "Sources/ask/PrintRun.swift", "Tests/AskTUITests/TerminalTeardownTests.swift"
    ]

    /// The entries of `baseline` that are clean or no longer exist, so should be removed from it.
    static func staleBaseline(_ baseline: Set<String>) throws -> Set<String> {
        var stale: Set<String> = []
        for path in baseline {
            let url = SourceStandards.repositoryRoot.appending(path: path)
            guard let text = try? String(contentsOf: url, encoding: .utf8),
                !violations(fileName: url.lastPathComponent, text: text).isEmpty
            else {
                stale.insert(path)
                continue
            }
        }
        return stale
    }

    /// `path: problem` for every file in `files`, other than those in `excluding`, that breaks a rule.
    static func violations(in files: [URL], excluding baseline: Set<String> = []) throws -> [String] {
        var found: [String] = []
        for file in files where !baseline.contains(relative(file)) {
            let text = try String(contentsOf: file, encoding: .utf8)
            for problem in violations(fileName: file.lastPathComponent, text: text) {
                found.append("\(relative(file)) \(problem)")
            }
        }
        return found
    }

    /// `path: N lines` for every file in `files` past ``lineCeiling``.
    static func overlongFiles(in files: [URL]) throws -> [String] {
        var found: [String] = []
        for file in files {
            let count = lineCount(try String(contentsOf: file, encoding: .utf8))
            if count > lineCeiling { found.append("\(relative(file)): \(count) lines") }
        }
        return found
    }

    /// The number of lines, counting a last line that has no newline and not counting an empty text.
    static func lineCount(_ text: String) -> Int {
        text.split(separator: "\n", omittingEmptySubsequences: false).count
            - (text.hasSuffix("\n") || text.isEmpty ? 1 : 0)
    }

    private static func relative(_ url: URL) -> String {
        url.path.replacingOccurrences(of: SourceStandards.repositoryRoot.path + "/", with: "")
    }
}
