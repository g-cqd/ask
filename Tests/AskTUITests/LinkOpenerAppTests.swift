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

    @Test func `a refusal is said as the openers gave it, and a command is not run yet`() {
        #expect(
            LinkOpener.perform("file:///a", opening: .refused("Not run: -rf would be read as an option."))
                == "Not run: -rf would be read as an option."
        )
        #expect(
            LinkOpener.perform("file:///a", opening: .command(["code", "/a"], rule: 0))?.hasPrefix("Not run") == true
        )
        #expect(
            LinkOpener.perform("https://x.example", opening: .app("No Such App 1234"))?.contains("No Such App 1234")
                == true
        )
    }
}
