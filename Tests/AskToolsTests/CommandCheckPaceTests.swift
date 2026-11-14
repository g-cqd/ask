import Foundation
import Testing

@testable import AskTools

/// What the check before a command costs (diary 2026-11-14-07): shellcheck's start is 21 ms and the shell's parse up to 10, on every
/// command, so they run side by side.
@Suite("The check before a command runs its two parts together", .timeLimit(.minutes(1)))
struct CommandCheckPaceTests {
    @Test func `shellcheck starts while the shell parses, not after it`() async throws {
        // The shell here ends its parse only once shellcheck has started; one after the other, it would give up and fail.
        let wait = """
            n=0
            while [ ! -e "$(dirname "$0")/lint-started" ]; do
                n=$((n + 1)); [ "$n" -lt 300 ] || exit 9
                /bin/sleep 0.01
            done
            """
        let fixture = try CheckFixture(beforeParse: wait, shellcheck: #": > "$(dirname "$0")/lint-started""#)
        defer { fixture.remove() }
        let checked = await CommandCheck.check("echo hi", shell: fixture.shell, path: fixture.path)
        #expect(checked == CommandCheck.Result(), "parsed, no finding, in time")
    }

    @Test func `a command that does not parse is told so without waiting for shellcheck`() async throws {
        // A shellcheck that would take its whole deadline: the parse's answer does not wait for it to be stopped.
        let fixture = try CheckFixture(shellcheck: "exec /bin/sleep 30")
        defer { fixture.remove() }
        let clock = ContinuousClock()
        var checked = CommandCheck.Result()
        let took = await clock.measure {
            checked = await CommandCheck.check(
                #"echo "open"#,
                shell: fixture.shell,
                path: fixture.path,
                deadline: .seconds(4)
            )
        }
        #expect(checked.syntaxError?.contains("unexpected EOF") == true)
        #expect(!checked.unchecked && checked.findings.isEmpty)
        #expect(took < .seconds(2), "it took \(took)")
    }
}
