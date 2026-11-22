internal import AppKit
internal import Foundation
internal import Testing

@testable import AskTUI

/// Run against a pasteboard of its own, never the person's clipboard.
@Suite("The host pasteboard is written and read through NSPasteboard (roadmap 0082)")
struct HostPasteboardTests {
    private func withPasteboard(_ body: (NSPasteboard) -> Void) {
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("ask-test-\(UUID().uuidString)"))
        defer { pasteboard.releaseGlobally() }
        body(pasteboard)
    }

    @Test func `what is written is read back exactly`() {
        withPasteboard { pasteboard in
            let text = "héllo\nwörld 日本"
            #expect(HostPasteboard.write(text, to: pasteboard) == .copied)
            #expect(HostPasteboard.read(from: pasteboard) == .text(text))
        }
    }

    @Test func `a large text goes through whole`() {
        withPasteboard { pasteboard in
            let text = String(repeating: "0123456789abcdef", count: 100_000)
            #expect(HostPasteboard.write(text, to: pasteboard) == .copied)
            #expect(HostPasteboard.read(from: pasteboard) == .text(text))
        }
    }

    @Test func `with no file copied, the picture is the pasteboard's PNG data; empty data is none`() {
        withPasteboard { pasteboard in
            pasteboard.clearContents()
            #expect(pasteboard.setData(Data([0x89, 0x50, 0x4E, 0x47]), forType: .png))
            #expect(HostPasteboard.picture(on: pasteboard, files: []) == [0x89, 0x50, 0x4E, 0x47])
            pasteboard.clearContents()
            #expect(pasteboard.setData(Data(), forType: .png))
            #expect(HostPasteboard.picture(on: pasteboard, files: []) == nil, "an empty picture is no picture")
        }
    }

    @Test func `a private pasteboard is never denied`() {
        withPasteboard { #expect($0.accessBehavior != .alwaysDeny) }
    }

    @Test func `an empty pasteboard reads as nothing`() {
        withPasteboard { pasteboard in
            pasteboard.clearContents()
            #expect(HostPasteboard.read(from: pasteboard) == .empty)
        }
    }

    /// Finder's copy of a file: the file's URL, its name as text, and an icon picture (owner, 2026-11-21: "it always pastes the last
    /// component of the path of the file").
    private func copyLikeFinder(_ paths: [String], on pasteboard: NSPasteboard) {
        pasteboard.clearContents()
        _ = pasteboard.writeObjects(paths.map { URL(fileURLWithPath: $0) as NSURL })
        pasteboard.addTypes([.string, .tiff], owner: nil)
        _ = pasteboard.setString(
            paths.map { ($0 as NSString).lastPathComponent }.joined(separator: "\r"),
            forType: .string
        )
        _ = pasteboard.setData(Data([0x4D, 0x4D, 0x00, 0x2A]), forType: .tiff)
    }

    @Test func `a copied file reads as its full path, not its name or its icon`() {
        withPasteboard { pasteboard in
            copyLikeFinder(["/Users/someone/Documents/report.pdf"], on: pasteboard)
            #expect(HostPasteboard.read(from: pasteboard) == .text("/Users/someone/Documents/report.pdf"))
        }
    }

    @Test func `several copied files read as their paths, each quoted when it holds a blank or a quote`() {
        withPasteboard { pasteboard in
            copyLikeFinder(["/tmp/a.txt", "/tmp/my report.pdf", "/tmp/it's.md"], on: pasteboard)
            #expect(
                HostPasteboard.read(from: pasteboard) == .text(#"/tmp/a.txt '/tmp/my report.pdf' '/tmp/it'\''s.md'"#)
            )
        }
    }

    @Test func `a copied file whose name holds a control character reads as the text beside it`() {
        withPasteboard { pasteboard in
            copyLikeFinder(["/tmp/bad\u{1B}name.txt"], on: pasteboard)
            #expect(HostPasteboard.read(from: pasteboard) == .text("bad\u{1B}name.txt"))
        }
    }
}
