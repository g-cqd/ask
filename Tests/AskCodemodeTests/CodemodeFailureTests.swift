import Testing

@testable import AskCodemode

/// How a script fails, and what a failure leaves (ADR-0156): each is something the model reads and acts on.
@Suite("A script that fails says why, and keeps what it had said", .timeLimit(.minutes(1)))
struct CodemodeFailureTests {
    private func run(_ code: String, tools: ScriptedTools = ScriptedTools()) async -> CodemodeResult {
        await tools.run(code)
    }

    @Test func `a tool that fails rejects with its own words, which a script can catch`() async {
        let result = await run(
            #"try { await tools.fail({ p: 1 }); } catch (e) { return [e instanceof Error, e.message]; }"#
        )
        #expect(result == CodemodeResult(items: [CodemodeItem(text: #"[true,"no such file: {\"p\":1}"]"#)]))
    }

    @Test func `one it does not catch fails the script with those words`() async {
        let result = await run("text('before'); await tools.fail({});")
        #expect(result.items == [CodemodeItem(text: "before")], "what it had said is kept")
        #expect(result.failure == "Error: no such file: {}")
    }

    @Test func `allSettled keeps the calls that succeeded`() async {
        let result = await run(
            "const s = await Promise.allSettled([tools.read({}), tools.fail({})]); return s.map((x) => x.status);"
        )
        #expect(result == CodemodeResult(items: [CodemodeItem(text: #"["fulfilled","rejected"]"#)]))
    }

    @Test func `a script that throws says what, and on which of its lines`() async {
        let result = await run("const a = 1;\nconst b = 2;\nnull.x;\nreturn a + b;")
        #expect(result.failure?.hasPrefix("TypeError: null is not an object") == true)
        #expect(result.failure?.hasSuffix("(codemode.js:3)") == true, "\(result.failure ?? "nil")")
        let thrown = await run(#"throw new Error("mine");"#)
        #expect(thrown.failure == "Error: mine (codemode.js:1)")
        let odd = await run("throw 'just a string';")
        #expect(odd.failure == "just a string")
    }

    @Test func `a script that does not parse fails before anything runs`() async {
        let tools = ScriptedTools()
        let result = await run("await tools.read({});\nreturn (;", tools: tools)
        #expect(result.failure?.hasPrefix("SyntaxError: ") == true)
        #expect(result.failure?.hasSuffix("(codemode.js:2)") == true, "\(result.failure ?? "nil")")
        #expect(tools.calls.isEmpty)
    }

    @Test func `a script that waits on what nothing can settle fails at once`() async {
        let result = await run("text('said'); await new Promise(() => {}); return 1;")
        #expect(result.items == [CodemodeItem(text: "said")])
        #expect(
            result.failure == "The script is waiting on a promise that nothing can settle: no tool call is pending."
        )
    }

    @Test func `a call it did not wait for is counted as still running when it ends`() async {
        let tools = ScriptedTools()
        let result = await run("tools.held({}); tools.held({}); await tools.read({}); return 1;", tools: tools)
        #expect(result == CodemodeResult(items: [CodemodeItem(text: "1")], unsettled: 2))
        tools.release()
    }

    @Test func `a script that waits on a call goes on when the call answers`() async {
        let tools = ScriptedTools()
        async let result = run("const a = await tools.held({ n: 1 }); return a;", tools: tools)
        await tools.heldArrived()
        tools.release()
        #expect(await result == CodemodeResult(items: [CodemodeItem(text: #"held {"n":1}"#)]))
    }

    @Test func `output past what may be held fails the script, whatever it catches`() async {
        let result = await run(
            "try { for (;;) text('x'.repeat(1 << 16)); } catch (e) { text('caught'); } return 'done';"
        )
        #expect(
            result.failure
                == "The script said more than 1048576 characters; write large data to a file with a tool instead."
        )
        #expect(result.items.count == 16)
        let many = await run("try { for (;;) text(''); } catch (e) {} return 1;")
        #expect(many.failure == "The script made more than 10000 text and console calls.")
        #expect(many.items.count == 10_000)
    }

    /// The result crosses to the keeper as one line of at most 8 MiB: the worst a script can say has to fit in it.
    @Test func `the most a script may say fits in one line of the wire`() {
        let worstCharacters = CodemodeVM.maximumCharacters * 6
        let worstItems = CodemodeVM.maximumItems * #"{"text":"","console":false},"#.utf8.count
        #expect(worstCharacters + worstItems + 4096 < 8 << 20)
    }
}
