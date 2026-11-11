internal import Foundation
internal import Testing

@testable import AskTUI

/// A link opened in the app the person's openers name (roadmap 0216, ADR-0148): found by bundle identifier or by name, said when it
/// is missing, and never for a file that is not there.
@Suite("A link opens in the app the person chose")
struct LinkOpenerAppTests {
    private static let calculator = URL(fileURLWithPath: "/System/Applications/Calculator.app")

    @Test func `the app is found by name or by bundle identifier`() throws {
        let file = FileManager.default.temporaryDirectory.appending(path: "ask-opener-\(UUID().uuidString).txt")
        try Data("x".utf8).write(to: file)
        defer { try? FileManager.default.removeItem(at: file) }
        #expect(LinkOpener.action(for: file.absoluteString, app: "Calculator") == .openWith(file, app: Self.calculator))
        #expect(
            LinkOpener.action(for: file.absoluteString, app: "com.apple.calculator")
                == .openWith(file, app: Self.calculator)
        )
        #expect(
            LinkOpener.action(for: "https://example.com", app: "Calculator")
                == .openWith(URL(string: "https://example.com")!, app: Self.calculator)
        )
    }

    @Test func `an app that is not there is said, and a file that is not there is not opened`() {
        #expect(
            LinkOpener.action(for: "https://example.com", app: "No Such App 1234") == .missingApp("No Such App 1234")
        )
        #expect(LinkOpener.action(for: "file:///nowhere/at/all.txt", app: "Calculator") == .refuse)
        #expect(LinkOpener.action(for: "vscode://x", app: "Calculator") == .refuse)
    }

    @Test func `a refusal is said as the openers gave it, and a command is not run for a file that is not there`() {
        #expect(
            LinkOpener.perform("file:///a", opening: .refused("Not run: -rf would be read as an option."))
                == "Not run: -rf would be read as an option."
        )
        #expect(
            LinkOpener.perform("file:///a", opening: .command(["code", "/a"], rule: 0))?.hasPrefix("Not opened") == true
        )
        // The wording only: performing it would open the link the usual way, as roadmap 0216 says, and a test clicks nothing.
        let missing = LinkOpener.missingAppNotice("No Such App 1234", usual: nil)
        #expect(missing.contains("No Such App 1234") && ClipboardNotice.needsAttention(missing))
        #expect(
            LinkOpener.missingAppNotice("X", usual: "Nothing opened https://x.example.")
                .hasSuffix("Nothing opened https://x.example.")
        )
    }

    /// The review of 2026-11-11: an app opener must not undo "what would run is only shown" (roadmap 0075, note n33). An app bundle is
    /// a directory, so `"folder": "Finder"` launched it; a terminal as the file app ran a script.
    @Test func `an app, an installer or a compiled program is shown in the Finder, whatever app the openers name`()
        throws
    {
        for target in [Self.calculator, URL(fileURLWithPath: "/bin/ls")] {
            for app in ["Finder", "Terminal", "Calculator"] {
                #expect(
                    LinkOpener.action(for: target.absoluteString, app: app) == .reveal(target),
                    "\(target) in \(app)"
                )
            }
        }
    }

    /// The owner, 2026-11-11: a script opens in the app the openers name, as any document does. A plain click still only shows it.
    @Test func `a script opens in the app the openers name, and a plain click still only shows it`() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "ask-scripts-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        // A script by its type, one by its first line and its execute bit, and one the system calls a shell script.
        let typed = directory.appending(path: "run.command")
        let marked = directory.appending(path: "build")
        let shell = directory.appending(path: "quality.sh")
        for (file, executable) in [(typed, false), (marked, true), (shell, true)] {
            try Data("#!/bin/sh\necho hi\n".utf8).write(to: file)
            try FileManager.default.setAttributes(
                [.posixPermissions: executable ? 0o755 : 0o644],
                ofItemAtPath: file.path
            )
        }
        for file in [typed, marked, shell] {
            let target = LinkOpener.action(for: file.absoluteString)
            guard case .reveal(let shown) = target else {
                Issue.record("a plain click should only show \(file.lastPathComponent): \(target)")
                continue
            }
            #expect(
                LinkOpener.action(for: file.absoluteString, app: "Calculator") == .openWith(shown, app: Self.calculator)
            )
            #expect(
                LinkOpener.runsCommand(file.absoluteString, opening: .command(["code", file.path], rule: 0)),
                "\(file.lastPathComponent) by a command"
            )
        }
        #expect(!LinkOpener.runsCommand("file:///bin/ls", opening: .command(["code", "/bin/ls"], rule: 0)))
    }

    /// Step 4: a command is offered only what a plain click would open, as an app is (the review of 2026-11-11).
    @Test func `a command runs for what would open, and never for what would run or is not there`() throws {
        let file = FileManager.default.temporaryDirectory.appending(path: "ask-opener-\(UUID().uuidString).txt")
        try Data("x".utf8).write(to: file)
        defer { try? FileManager.default.removeItem(at: file) }
        let command = LinkOpening.command(["code", file.path], rule: 0)
        #expect(LinkOpener.runsCommand(file.absoluteString + "#L3", opening: command))
        #expect(LinkOpener.runsCommand("https://example.com/a", opening: command))
        #expect(!LinkOpener.runsCommand("file:///bin/ls", opening: command))
        #expect(!LinkOpener.runsCommand(Self.calculator.absoluteString, opening: command))
        #expect(!LinkOpener.runsCommand("file:///nowhere/at/all.txt", opening: command))
        #expect(!LinkOpener.runsCommand(file.absoluteString, opening: .app("Xcode")))
        #expect(!LinkOpener.runsCommand(file.absoluteString, opening: .system))
    }

    @Test func `the opener's question offers this time, always and deny, this time checked`() {
        let asked = PendingApproval(id: 1, question: "q", kind: .opener(remembers: true))
        #expect(asked.options.map(\.choice) == [.once, .session, .deny] && asked.checked == 0)
        #expect(asked.options[1].label == "Always allow this command" && asked.options[1].said == "always allowed")
        #expect(
            PendingApproval(id: 1, question: "q", kind: .opener(remembers: false)).options.map(\.choice) == [
                .once, .deny
            ]
        )
    }
}
