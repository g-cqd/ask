import Foundation
import Testing

@testable import AskTools

/// What the check before a command costs (diary 2026-11-14-07): shellcheck's start is 21 ms and the shell's parse up to 10, on every
/// command, so they run side by side.
@Suite("The check before a command runs its two parts together", .timeLimit(.minutes(3)))
struct CommandCheckPaceTests {
    /// Neither test reads a clock: on a loaded CI runner a test of this suite took 24 s, and "in under two seconds" failed there
    /// (run 43640535106). What is checked is the order of events; the limits only bound a broken build's run.
    @Test func `shellcheck starts while the shell parses, not after it`() async throws {
        // The shell here ends its parse only once shellcheck has started; one after the other, it would give up and fail.
        let wait = """
            n=0
            while [ ! -e "$(dirname "$0")/lint-started" ]; do
                n=$((n + 1)); [ "$n" -lt 3000 ] || exit 9
                /bin/sleep 0.01
            done
            """
        let fixture = try CheckFixture(beforeParse: wait, shellcheck: #": > "$(dirname "$0")/lint-started""#)
        defer { fixture.remove() }
        let checked = await CommandCheck.check(
            "echo hi",
            shell: fixture.shell,
            path: fixture.path,
            deadline: .seconds(100)
        )
        #expect(checked == CommandCheck.Result(), "parsed, and nothing found")
    }

    @Test func `a command that does not parse is told so without waiting for shellcheck`() async throws {
        // A shellcheck that ends only when the test lets it: the parse's answer has to come while it still runs.
        let held = """
            n=0
            while [ ! -e "$(dirname "$0")/release" ]; do
                n=$((n + 1)); [ "$n" -lt 3000 ] || break
                /bin/sleep 0.01
            done
            : > "$(dirname "$0")/finished"
            """
        let fixture = try CheckFixture(shellcheck: held)
        defer { fixture.remove() }
        let checked = await CommandCheck.check(
            #"echo "open"#,
            shell: fixture.shell,
            path: fixture.path,
            deadline: .seconds(100)
        )
        let finished = FileManager.default.fileExists(atPath: fixture.directory.appendingPathComponent("finished").path)
        #expect(!finished, "the answer waited for shellcheck to end")
        FileManager.default.createFile(atPath: fixture.directory.appendingPathComponent("release").path, contents: nil)
        #expect(checked.syntaxError?.contains("unexpected EOF") == true)
        #expect(!checked.unchecked && checked.findings.isEmpty)
    }
}
