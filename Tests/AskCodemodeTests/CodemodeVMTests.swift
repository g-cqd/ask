import Testing

@testable import AskCodemode

/// A script's surface, copied from pi on purpose (ADR-0156): the body of an async function whose only way out is the tools.
@Suite("A script is an async function's body: it calls tools, says text, and returns", .timeLimit(.minutes(1)))
struct CodemodeVMTests {
    private func run(_ code: String, tools: ScriptedTools = ScriptedTools()) async -> CodemodeResult {
        await tools.run(code)
    }

    private func text(_ items: String...) -> [CodemodeItem] { items.map { CodemodeItem(text: $0) } }

    @Test func `it awaits a tool at the top level and returns what it made of it`() async {
        let tools = ScriptedTools()
        let result = await run(#"const a = await tools.read({ path: "x" }); return a.length;"#, tools: tools)
        #expect(result == CodemodeResult(items: text("17")))
        #expect(tools.calls == [#"read {"path":"x"}"#], "the arguments are JSON, as the tool takes them")
    }

    @Test func `text is said in order, a string as it is and anything else as JSON, and the return comes last`() async {
        let result = await run(
            #"text("one"); text({ a: [1, 2] }); text(3); text(null); text(undefined); return "done";"#
        )
        #expect(result == CodemodeResult(items: text("one", #"{"a":[1,2]}"#, "3", "null", "undefined", "done")))
    }

    @Test func `a script that returns nothing, or undefined, adds nothing`() async {
        #expect(await run("text('only this');") == CodemodeResult(items: text("only this")))
        #expect(await run("return undefined;") == CodemodeResult())
        #expect(await run("return null;") == CodemodeResult(items: text("null")))
        #expect(await run(#"return { ok: true };"#) == CodemodeResult(items: text(#"{"ok":true}"#)))
    }

    @Test func `console lines are kept apart, their arguments joined by spaces`() async {
        let result = await run(#"console.log("a", 1, { b: 2 }); console.error("bad"); console.warn(); text("t");"#)
        let expected = [
            CodemodeItem(text: #"a 1 {"b":2}"#, console: true), CodemodeItem(text: "bad", console: true),
            CodemodeItem(text: "", console: true), CodemodeItem(text: "t")
        ]
        #expect(result == CodemodeResult(items: expected))
    }

    @Test func `many calls run at once, and their answers come back in the order asked for`() async {
        let tools = ScriptedTools()
        let result = await run(
            "const all = await Promise.all(Array.from({ length: 50 }, (_, i) => tools.read({ i }))); return all.map((a) => a.length);",
            tools: tools
        )
        #expect(tools.calls.count == 50)
        #expect(result.items.first?.text.hasPrefix("[12,12,12,12,12,12,12,12,12,12,13,") == true)
    }

    @Test func `a tool is called by its name or by the identifier made of it, and no arguments are an empty object`()
        async
    {
        let tools = ScriptedTools()
        _ = await run(
            #"await tools.mcp__dev_radius__search({ q: 1 }); await tools["mcp__dev-radius__search"](); await tools.read();"#,
            tools: tools
        )
        #expect(tools.calls == [#"mcp__dev-radius__search {"q":1}"#, "mcp__dev-radius__search {}", "read {}"])
    }

    @Test func `ALL_TOOLS lists what can be called, by identifier, with what each is for`() async {
        let result = await run("return ALL_TOOLS.map((t) => t.name + ': ' + t.description);")
        #expect(
            result.items.first?.text
                == #"["read: Read a file.","fail: Always fails.","held: Answers when the test lets it.","mcp__dev_radius__search: Search."]"#
        )
    }

    @Test func `exit ends the script successfully, keeping what it had said`() async {
        #expect(await run(#"text("kept"); exit(); text("never");"#) == CodemodeResult(items: text("kept")))
        #expect(
            await run(#"try { exit(); } catch (e) { text("caught"); } text("after");"#) == CodemodeResult(),
            "it cannot be caught"
        )
    }

    @Test func `nothing exists but the language and the surface`() async {
        let names = [
            "fetch", "require", "process", "setTimeout", "setInterval", "XMLHttpRequest", "WebAssembly", "print",
            "load", "readFile"
        ]
        let result = await run("return \(names).filter((n) => typeof globalThis[n] !== 'undefined');")
        #expect(result == CodemodeResult(items: text("[]")))
        let surface = await run(
            "return ['tools', 'text', 'console', 'exit', 'ALL_TOOLS', 'JSON', 'Promise', 'Date'].map((n) => typeof globalThis[n]);"
        )
        #expect(
            surface.items.first?.text
                == #"["object","function","object","function","object","object","function","function"]"#
        )
    }

    @Test func `the surface cannot be replaced from inside`() async {
        let tools = ScriptedTools()
        let result = await run(
            "try { tools.read = () => 'mine'; } catch (e) {} try { ALL_TOOLS.push(1); } catch (e) {} return [await tools.read({}), ALL_TOOLS.length];",
            tools: tools
        )
        #expect(result.items.first?.text == #"["read {}",4]"#)
    }
}
