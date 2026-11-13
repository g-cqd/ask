internal import Foundation
internal import Testing

@testable import AskCore

/// A write whose error is dropped is said, or given its reason (roadmap 0230, the owner's choice of a gate rule, 2026-11-13). `try?`
/// before a call that keeps the person's data (a session record, a saved credential, a copied list, a file written) hides the one
/// failure they would want to hear of: the line, or the comment line above it, must carry `// try?:` and why dropping it is right.
/// Closing a descriptor, removing a temporary and writing to the terminal are not in the rule: nothing of the person's is lost.
@Suite("A dropped write error carries its reason")
struct DroppedWriteErrorsTests {
    /// The calls that keep data.
    static let writes = [
        "recordThread(", "record(", ".append(.", "writeAll(", ".write(to:", ".copyItem(", ".moveItem(", "remember(",
        ".put(", "renewMCP(",
        "saveClaude(", "saveCodex(", "saveAgy(", ".save("
    ]

    /// `file:line` of each `try?` before a write with no reason, in `text`.
    static func offenders(in text: String, file: String) -> [String] {
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        return lines.indices.compactMap { index in
            let line = lines[index]
            guard let start = line.range(of: "try?"), !line.trimmingCharacters(in: .whitespaces).hasPrefix("//") else {
                return nil
            }
            let after = line[start.upperBound...]
            guard writes.contains(where: after.contains) else { return nil }
            let above = index > 0 ? lines[index - 1].trimmingCharacters(in: .whitespaces) : ""
            let reasoned = line.contains("// try?:") || (above.hasPrefix("//") && above.contains("try?:"))
            return reasoned ? nil : "\(file):\(index + 1)"
        }
    }

    @Test func `the rule finds a dropped write, and accepts one with its reason on the line or above it`() {
        let dropped = "func f() {\n    try? recorder.recordThread(.renamed(id, to: title))\n}\n"
        #expect(Self.offenders(in: dropped, file: "F.swift") == ["F.swift:2"])
        let sameLine = "    _ = try? file.saveAgy(result)  // try?: found again on the next request\n"
        let above = "    // try?: a cache, rebuilt from the session\n    try? data.write(to: url)\n"
        let notAWrite =
            "    defer { try? handle.close() }\n    try? connection.write(bytes)\n    let x = try? parse(text)\n"
        #expect(Self.offenders(in: sameLine + above + notAWrite, file: "F.swift").isEmpty)
    }

    @Test func `no source file drops a write's error without saying why`() throws {
        let root = SourceStandards.repositoryRoot.appending(path: "Sources")
        let files =
            FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil)?.compactMap { $0 as? URL } ?? []
        let found = try files.filter { $0.pathExtension == "swift" }
            .flatMap { file in
                Self.offenders(
                    in: try String(contentsOf: file, encoding: .utf8),
                    file: file.path.replacingOccurrences(of: root.path + "/", with: "")
                )
            }
        #expect(found.isEmpty, "say the failure to the person, or add `// try?: why`: \(found.sorted())")
    }
}
