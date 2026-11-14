import Testing

@testable import AskTools

@Suite("Commands found clean are remembered for their shell and PATH, within bounds")
struct CleanCommandsTests {
    @Test func `a remembered command is known for its shell and its PATH only`() {
        let clean = CleanCommands()
        #expect(!clean.contains("make", shell: "/bin/bash", path: "/usr/bin"))
        clean.remember("make", shell: "/bin/bash", path: "/usr/bin")
        #expect(clean.contains("make", shell: "/bin/bash", path: "/usr/bin"))
        #expect(!clean.contains("make ", shell: "/bin/bash", path: "/usr/bin"), "the text, exactly")
        #expect(!clean.contains("make", shell: "/bin/zsh", path: "/usr/bin"), "another shell parses on its own")
        #expect(
            !clean.contains("make", shell: "/bin/bash", path: "/opt/bin:/usr/bin"),
            "another PATH may hold a shellcheck"
        )
        #expect(!clean.contains("make", shell: "/bin/bash", path: nil))
    }

    @Test func `a changed PATH forgets what was remembered under the other`() {
        let clean = CleanCommands()
        clean.remember("make", shell: "/bin/bash", path: "/usr/bin")
        clean.remember("ls", shell: "/bin/bash", path: "/opt/bin")
        #expect(clean.contains("ls", shell: "/bin/bash", path: "/opt/bin"))
        #expect(!clean.contains("make", shell: "/bin/bash", path: "/usr/bin"))
    }

    @Test func `a long command is not kept, and a full memory starts again`() {
        let clean = CleanCommands()
        let long = String(repeating: "x", count: CleanCommands.maximumBytes + 1)
        clean.remember(long, shell: "/bin/bash", path: nil)
        #expect(!clean.contains(long, shell: "/bin/bash", path: nil))
        let atLimit = String(repeating: "x", count: CleanCommands.maximumBytes)
        clean.remember(atLimit, shell: "/bin/bash", path: nil)
        #expect(clean.contains(atLimit, shell: "/bin/bash", path: nil))
        for index in 0 ..< CleanCommands.kept { clean.remember("echo \(index)", shell: "/bin/bash", path: nil) }
        #expect(!clean.contains(atLimit, shell: "/bin/bash", path: nil), "full, it started again")
        #expect(clean.contains("echo \(CleanCommands.kept - 1)", shell: "/bin/bash", path: nil))
    }
}
