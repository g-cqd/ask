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

    @Test func `a private pasteboard is never denied`() {
        withPasteboard { #expect($0.accessBehavior != .alwaysDeny) }
    }

    @Test func `an empty pasteboard reads as nothing`() {
        withPasteboard { pasteboard in
            pasteboard.clearContents()
            #expect(HostPasteboard.read(from: pasteboard) == .empty)
        }
    }
}
