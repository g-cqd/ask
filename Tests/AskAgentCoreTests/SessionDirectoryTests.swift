import Foundation
import Testing

@testable import AskAgentCore

/// Where sessions live: one directory per project, one new file per run.
@Suite("Sessions live per project under the XDG state directory")
struct SessionDirectoryTests {
    private let now = Date(timeIntervalSince1970: 1_792_281_600)  // 2026-10-18T00:00:00Z, checked with Python

    @Test func `the state directory follows XDG_STATE_HOME, then the home directory`() {
        let xdg = SessionDirectory(project: "/Users/g/ask", environment: ["XDG_STATE_HOME": "/s"], home: "/h")
        #expect(xdg.path == "/s/ask/sessions/Users-g-ask")
        let home = SessionDirectory(project: "/Users/g/ask", environment: [:], home: "/h")
        #expect(home.path == "/h/.local/state/ask/sessions/Users-g-ask")
        let relative = SessionDirectory(project: "/p", environment: ["XDG_STATE_HOME": "rel"], home: "/h")
        #expect(relative.path == "/h/.local/state/ask/sessions/p")
    }

    @Test func `project names are flattened and kept readable`() {
        #expect(SessionDirectory.projectName("/Users/g/My Project/src") == "Users-g-My_Project-src")
        #expect(SessionDirectory.projectName("/") == "root")
        #expect(SessionDirectory.projectName("/a/../b") == "a-..-b")
    }

    @Test func `each run gets a new, sortable, distinct file name`() {
        let directory = SessionDirectory(project: "/p", environment: [:], home: "/h")
        let first = directory.newSessionPath(now: now)
        let second = directory.newSessionPath(now: now)
        #expect(first.hasPrefix("/h/.local/state/ask/sessions/p/20261018T000000Z-"))
        #expect(first.hasSuffix(".jsonl"))
        #expect(first != second)
    }
}
