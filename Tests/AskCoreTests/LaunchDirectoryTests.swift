internal import Testing

@testable import AskCore

/// ask started where the shell's directory was replaced under it (a volume mounted again) had no working directory at all, and ran
/// on with every path resolved against nothing.
@Suite("A launch without a working directory goes back to the shell's, or says so")
struct LaunchDirectoryTests {
    private let there: (String) -> Bool = { $0 == "/Volumes/Work/project" }

    @Test func `a known directory is kept, whatever the shell says`() {
        #expect(
            LaunchDirectory.resolve(current: "/a/b", shell: "/Volumes/Work/project", isDirectory: there) == .current
        )
        #expect(LaunchDirectory.resolve(current: "/a/b", shell: nil, isDirectory: there) == .current)
    }

    @Test func `with none, the shell's directory is entered when it is there`() {
        #expect(
            LaunchDirectory.resolve(current: "", shell: "/Volumes/Work/project", isDirectory: there)
                == .enter("/Volumes/Work/project")
        )
    }

    @Test func `with none and nowhere to go, it is missing`() {
        for shell in [nil, "", "relative/project", "/Volumes/Work/gone", "."] as [String?] {
            #expect(
                LaunchDirectory.resolve(current: "", shell: shell, isDirectory: there) == .missing,
                "\(shell ?? "nil")"
            )
        }
    }
}
