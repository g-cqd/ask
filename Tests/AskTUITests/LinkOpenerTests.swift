internal import Foundation
internal import Testing

@testable import AskTUI

/// What a click may open (roadmap 0075): web pages, mail, documents and folders in their apps. A file that would run (an app, a script,
/// an executable) is shown in the Finder instead, since a model could print the path of one; other schemes are not opened at all.
@Suite("A clicked link opens only what is safe to open")
struct LinkOpenerTests {
    @Test func `web pages, mail and documents open`() throws {
        #expect(LinkOpener.action(for: "https://example.com/a") == .open(URL(string: "https://example.com/a")!))
        #expect(LinkOpener.action(for: "mailto:a@b.org") == .open(URL(string: "mailto:a@b.org")!))
        let file = FileManager.default.temporaryDirectory.appending(path: "ask-link-\(UUID().uuidString).txt")
        try Data("x".utf8).write(to: file)
        defer { try? FileManager.default.removeItem(at: file) }
        #expect(LinkOpener.action(for: file.absoluteString) == .open(file))
        #expect(LinkOpener.action(for: FileManager.default.temporaryDirectory.absoluteString) != .refuse)
    }

    @Test func `anything that would run is shown in the Finder instead`() throws {
        let script = FileManager.default.temporaryDirectory.appending(path: "ask-link-\(UUID().uuidString).command")
        try Data("#!/bin/sh\n".utf8).write(to: script)
        defer { try? FileManager.default.removeItem(at: script) }
        for target in [
            URL(fileURLWithPath: "/bin/ls"), URL(fileURLWithPath: "/System/Applications/Calculator.app"), script
        ] {
            #expect(LinkOpener.action(for: target.absoluteString) == .reveal(target), "\(target)")
        }
    }

    @Test func `other schemes, and files that are not there, are not opened`() {
        for uri in [
            "javascript:alert(1)", "x-apple.systempreferences:com.apple.preference", "vscode://file/x", "ftp://x.org/a"
        ] {
            #expect(LinkOpener.action(for: uri) == .refuse, "\(uri)")
        }
        #expect(LinkOpener.action(for: "file:///nonexistent/\(UUID().uuidString)") == .refuse)
    }
}
