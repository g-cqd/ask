internal import Synchronization
import TerminalKitMarkdown
import Testing

@testable import AskTUI

/// Paths in replies and reasoning (roadmap 0215, note n31): shown relative to the project, or up to N folders above it; linked; a relative
/// one only when it exists, and nothing outside the project is looked for on the disk.
@Suite("Paths are shown short and linked")
struct PathDisplayTests {
    private static let files: Set<String> = ["/w/proj/Sources/a.swift", "/w/proj/Package.swift"]

    private func display(ancestors: Int? = 2, shortens: Bool = true, asked: Asked = Asked()) -> PathDisplay {
        PathDisplay(workspace: "/w/proj", home: "/Users/me", ancestors: ancestors, shortens: shortens) { path in
            asked.add(path)
            return Self.files.contains(path)
        }
    }

    /// What each found path shows and opens, by the text it covers.
    private func found(_ text: String, _ display: PathDisplay) -> [String: (shown: String, uri: String?)] {
        let bytes = Array(text.utf8)
        var result: [String: (String, String?)] = [:]
        for path in display.paths(in: text) {
            result[String(decoding: bytes[path.bytes], as: UTF8.self)] = (path.shown, path.uri)
        }
        return result
    }

    @Test func `inside the project a path is shown relative to it, its location kept, and opens the file`() throws {
        let path = try #require(found("See /w/proj/Sources/a.swift:12:5.", display())["/w/proj/Sources/a.swift:12:5"])
        // The place rides on the address until a link is made from it, so a row that wraps before `:12:5` keeps it (2026-11-11).
        #expect(path.shown == "Sources/a.swift:12:5" && path.uri == "file:///w/proj/Sources/a.swift#L12C5")
    }

    @Test func `up to the limit above the project it is shown from there, and beyond it as written`() {
        #expect(found("x /w/other/b.md y", display())["/w/other/b.md"]?.shown == "../other/b.md")
        #expect(found("x /elsewhere/b.md y", display())["/elsewhere/b.md"]?.shown == "/elsewhere/b.md")
        #expect(found("x /w/other/b.md y", display(ancestors: 0))["/w/other/b.md"]?.shown == "/w/other/b.md")
        #expect(
            found("x /elsewhere/b.md y", display(ancestors: nil))["/elsewhere/b.md"]?.shown == "../../elsewhere/b.md"
        )
    }

    @Test func `a home path is read through the home folder`() {
        let display = PathDisplay(workspace: "/Users/me/proj", home: "/Users/me", ancestors: 2, exists: { _ in false })
        let path = found("in ~/proj/README.md now", display)["~/proj/README.md"]
        #expect(path?.shown == "README.md" && path?.uri == "file:///Users/me/proj/README.md")
    }

    @Test func `a relative path is linked only when it exists in the project, and shown as written`() {
        let shown = found("Edit Sources/a.swift and Package.swift, not Sources/gone.swift or e.g. this.", display())
        #expect(
            shown["Sources/a.swift"]?.shown == "Sources/a.swift"
                && shown["Sources/a.swift"]?.uri == "file:///w/proj/Sources/a.swift"
        )
        #expect(shown["Package.swift"]?.uri == "file:///w/proj/Package.swift")
        #expect(shown["Sources/gone.swift"] == nil && shown["e.g"] == nil)
    }

    @Test func `nothing outside the project is looked for on the disk`() {
        let asked = Asked()
        _ = display(asked: asked).paths(in: "../../etc/passwd and ../secret.txt and /abs/x.txt and Sources/a.swift")
        #expect(asked.all.allSatisfy { $0.hasPrefix("/w/proj/") }, "\(asked.all)")
        #expect(asked.all.contains("/w/proj/Sources/a.swift"))
    }

    @Test func `addresses, single words and options are not paths`() {
        let text = "Open https://example.com/a.html or mail me@example.com, see /usr, run -o out.txt and a // comment."
        #expect(found(text, display()).keys.sorted() == [])
    }

    @Test func `as written, a path keeps its text and still links`() {
        let path = found("See /w/proj/Sources/a.swift.", display(shortens: false))["/w/proj/Sources/a.swift"]
        #expect(path?.shown == "/w/proj/Sources/a.swift" && path?.uri == "file:///w/proj/Sources/a.swift")
    }

    /// The paths the existence check was asked about.
    // SAFETY: every access goes through the mutex.
    final class Asked: @unchecked Sendable {
        private let asked = Mutex<[String]>([])
        var all: [String] { asked.withLock { $0 } }
        func add(_ path: String) { asked.withLock { $0.append(path) } }
    }
}
