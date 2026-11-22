import Foundation
import Testing

@testable import AskTools

/// A `python3` that is not the system's is asked where it is under a profile that writes nothing, and an answer naming `/`, the
/// home or a folder above it is refused (security audit 2026-11-22, HIGH-09): a `python3` planted on the `PATH` neither acts
/// outside the sandbox nor widens what a script may read.
@Suite("Asking a Python where it is")
struct CodemodePythonQuestionTests {
    private let folder = FileManager.default.temporaryDirectory.appending(path: "ask-python-\(UUID().uuidString)").path

    /// A `python3` that answers `lines`, after running `before`.
    private func planted(_ lines: [String], before: String = "") throws -> String {
        try FileManager.default.createDirectory(atPath: folder, withIntermediateDirectories: true)
        let path = folder + "/python3"
        let script = "#!/bin/sh\n" + before + "\n" + lines.map { "echo '\($0)'" }.joined(separator: "\n") + "\n"
        try Data(script.utf8).write(to: URL(filePath: path))
        #expect(chmod(path, 0o755) == 0)
        return path
    }

    @Test func `an answer naming the root, the home or a folder above it gives no interpreter`() async throws {
        defer { try? FileManager.default.removeItem(atPath: folder) }
        let home = "/Users/someone"
        for roots in [
            ["/", "/"], ["/Users/someone", "/usr/lib"], ["/Users", "/usr/lib"], ["/usr/lib", "/Users/someone"]
        ] {
            let python = try planted(["/usr/bin/true"] + roots)
            #expect(await CodemodePython.interpreter(python, home: home) == nil, "\(roots)")
        }
        let fine = try planted(["/usr/bin/true", "/usr/lib", "/Users/someone/.pyenv/versions/3.12"])
        #expect(
            await CodemodePython.interpreter(fine, home: home)?.roots == [
                "/usr/lib", "/Users/someone/.pyenv/versions/3.12"
            ]
        )
    }

    @Test func `a planted python3 writes nothing while it is asked`() async throws {
        defer { try? FileManager.default.removeItem(atPath: folder) }
        let mark = folder + "/escaped"
        let python = try planted(["/usr/bin/true", "/usr/lib", "/usr/lib"], before: "touch '\(mark)'")
        #expect(!CodemodePython.isSystemOwned(python))
        #expect(await CodemodePython.interpreter(python) != nil, "it still answers")
        #expect(!FileManager.default.fileExists(atPath: mark), "but what it tried to write was refused")
    }

    @Test func `the system's own python3 is root's, asked as it is`() {
        #expect(CodemodePython.isSystemOwned("/bin/sh"))
        #expect(!CodemodePython.isSystemOwned(NSTemporaryDirectory() + "nothing"))
    }
}
