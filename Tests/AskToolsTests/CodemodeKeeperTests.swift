import AskCodemode
import Synchronization
import Testing

@testable import AskTools

/// The keeper of a script's process (ADR-0156): it runs the tools the script asks for, and holds the script to its limits,
/// each a failure that says which.
@Suite("A script's process is given the script, served its calls, and held to its limits", .timeLimit(.minutes(1)))
struct CodemodeKeeperTests {
    /// A caller for scripts that call nothing.
    private let none: CodemodeVM.Caller = { _, _ in .success("") }
    private let tools = [
        CodemodeCallable(name: "read", description: "Read."), CodemodeCallable(name: "fail", description: "Fails.")
    ]

    /// Answers `read` with its arguments and fails `fail`, and counts the calls.
    private final class Tools: Sendable {
        private let made = Mutex(0)
        var count: Int { made.withLock { $0 } }

        func call(_ tool: String, _ arguments: String) async -> Result<String, CodemodeCallFailure> {
            made.withLock { $0 += 1 }
            return tool == "read" ? .success("read \(arguments)") : .failure(CodemodeCallFailure("no such file"))
        }
    }

    private func keeper(_ start: @escaping CodemodeChild.Start = CodemodeChildren.inProcess) -> CodemodeKeeper {
        CodemodeKeeper(start: start, scripts: CodemodeLimiter(2))
    }

    @Test func `a script's calls are run, and what it came to comes back`() async {
        let served = Tools()
        let result = await keeper()
            .run(
                #"const a = await tools.read({ path: "x" }); text(a); try { await tools.fail({}); } catch (e) { return e.message; }"#,
                tools: tools,
                limits: CodemodeLimits()
            ) { await served.call($0, $1) }
        #expect(
            result
                == CodemodeResult(items: [CodemodeItem(text: #"read {"path":"x"}"#), CodemodeItem(text: "no such file")]
                )
        )
        #expect(served.count == 2)
    }

    @Test func `every call of a script that makes many is run, and counted as it begins and ends`() async {
        let served = Tools()
        let progress = Mutex<[String]>([])
        let result = await keeper()
            .run(
                "const all = await Promise.all(Array.from({ length: 60 }, (_, i) => tools.read({ i }))); return all.length;",
                tools: tools,
                limits: CodemodeLimits(callsInFlight: 4),
                call: { await served.call($0, $1) },
                called: { began, ended in progress.withLock { $0.append("\(began)/\(ended)") } }
            )
        #expect(result == CodemodeResult(items: [CodemodeItem(text: "60")]))
        #expect(served.count == 60)
        #expect(progress.withLock { $0.last } == "60/60")
    }

    @Test func `a script past its deadline is stopped, and says how to ask for longer`() async {
        let limits = CodemodeLimits(deadline: .milliseconds(40))
        let result = await keeper(CodemodeChildren.silent)
            .run("while (true) {}", tools: [], limits: limits, call: none)
        let expected =
            "The script ran past its deadline of 0.04 s and was stopped. "
            + #"A first line `// @options: {"timeout_ms": …}` allows up to 600000."#
        #expect(result == CodemodeResult(failure: expected))
    }

    @Test func `a process that ended itself for its memory says so, and one that died says how`() async {
        let memory = await keeper(CodemodeChildren.gone(exit: 86))
            .run("x", tools: [], limits: CodemodeLimits(), call: none)
        #expect(memory.failure == "The script took more than 256 MiB of memory and was stopped.")
        let died = await keeper(CodemodeChildren.gone(exit: 139))
            .run("x", tools: [], limits: CodemodeLimits(), call: none)
        #expect(died.failure == "The process that ran the script ended before it answered (exit 139).")
    }

    /// What a script says reaches its keeper as it says it. The keeper is stopped here once the script's call has arrived, which
    /// comes after what it said: no clock decides what the keeper had heard.
    @Test func `a script that is stopped keeps what it had said until then`() async {
        let said = [CodemodeItem(text: "before"), CodemodeItem(text: "a line", console: true)]
        let keeper = keeper(CodemodeChildren.saying(said))
        let arrived = AsyncStream<Void>.makeStream()
        let never = AsyncStream<Void>.makeStream()
        let running = Task {
            await keeper.run("x", tools: [], limits: CodemodeLimits(deadline: .seconds(300))) { _, _ in
                arrived.continuation.yield()
                // Answered only by the script's end: the wait is over when the call is cancelled.
                for await _ in never.stream {}
                return .success("")
            }
        }
        for await _ in arrived.stream { break }
        running.cancel()
        #expect(await running.value == CodemodeResult(items: said, failure: "The script was stopped."))
    }

    /// A script's process holds itself to what a script may say; one that does not is stopped by its keeper.
    @Test func `a process that says more than a script may is stopped, with what a script may say`() async {
        let many = [CodemodeItem](repeating: CodemodeItem(text: "x"), count: CodemodeVM.maximumItems + 1)
        let result = await keeper(CodemodeChildren.saying(many))
            .run("x", tools: [], limits: CodemodeLimits(deadline: .seconds(300)), call: none)
        #expect(result.items.count == CodemodeVM.maximumItems)
        #expect(result.failure?.hasPrefix("The script said more than 1048576 characters") == true)
    }

    @Test func `a process that cannot start is a failure, not a wait`() async {
        let result = await keeper({ _ in nil })
            .run("return 1;", tools: [], limits: CodemodeLimits(), call: none)
        #expect(result.failure == "ask could not start the process that runs a script.")
    }

    @Test func `two scripts run at once in a process, and a third waits for one to end`() async {
        let scripts = CodemodeLimiter(2)
        let none = none
        let keeper = CodemodeKeeper(start: CodemodeChildren.silent, scripts: scripts)
        let limits = CodemodeLimits(deadline: .seconds(30))
        let held = (0 ..< 2)
            .map { _ in Task { await keeper.run("x", tools: [], limits: limits, call: none) } }
        let third = Task {
            await CodemodeKeeper(start: CodemodeChildren.inProcess, scripts: scripts)
                .run("return 'third';", tools: [], limits: CodemodeLimits(), call: none)
        }
        await scripts.waiting(1)
        #expect(scripts.free == 0, "two hold the places, the third waits")
        held[0].cancel()
        #expect(await third.value == CodemodeResult(items: [CodemodeItem(text: "third")]))
        held[1].cancel()
        for task in held { #expect(await task.value.failure == "The script was stopped.") }
    }

    /// A script's result crosses to its keeper as one line, and the connection takes lines of 8 MiB. Found with Python's first
    /// run (diary 2026-11-16-02): a result past that was dropped, and the script "ran past its deadline" two minutes later.
    @Test func `the most a script may say comes back whole, however it is escaped on the way`() async {
        // Control characters are six bytes each on the wire: the worst a script can do with a character.
        let code = "text('\\u0001'.repeat(\(CodemodeVM.maximumCharacters - 3))); return 'end';"
        let result = await keeper().run(code, tools: [], limits: CodemodeLimits(deadline: .seconds(30)), call: none)
        #expect(result.failure == nil)
        #expect(result.items.count == 2 && result.items.first?.text.utf16.count == CodemodeVM.maximumCharacters - 3)
        #expect(result.items.last?.text == "end")
    }

    @Test func `as many items as a script may make come back whole`() async {
        let code = "for (let i = 1; i < \(CodemodeVM.maximumItems); i++) console.log(''); return 1;"
        let result = await keeper().run(code, tools: [], limits: CodemodeLimits(deadline: .seconds(30)), call: none)
        #expect(result.failure == nil && result.items.count == CodemodeVM.maximumItems)
    }

    @Test func `a child whose message is longer than a line may be fails the script at once, and says so`() async {
        let oversized: CodemodeChild.Start = { _ in
            let (incoming, lines) = AsyncStream<[UInt8]>.makeStream()
            return CodemodeChild(
                incoming: incoming,
                send: { _ in lines.yield([UInt8](repeating: 0x78, count: (8 << 20) + 1)) },
                close: {
                    lines.finish()
                    return nil
                }
            )
        }
        // Thirty seconds of deadline: a keeper that waited for it would fail the test's own time limit first.
        let result = await keeper(oversized)
            .run("x", tools: [], limits: CodemodeLimits(deadline: .seconds(300)), call: none)
        #expect(
            result.failure
                == "The script's result is too large to return. Return less, or write it to a file with a tool."
        )
    }
}
