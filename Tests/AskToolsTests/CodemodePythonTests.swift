import AskCodemode
import Foundation
import Synchronization
import Testing

@testable import AskTools

/// A codemode script in Python (ADR-0156): the first `python3` on the `PATH`, under a profile that lets it reach its own
/// interpreter and nothing else, speaking to its keeper as the JavaScript host does. These run that Python, sandboxed.
@Suite(
    "A Python script calls the tools as a JavaScript one does, and can reach nothing else",
    .enabled(if: PythonOnPath.first != nil, "no python3 on the PATH"),
    .timeLimit(.minutes(2))
)
struct CodemodePythonTests {
    private let tools = [
        CodemodeCallable(name: "read", description: "Read a file."),
        CodemodeCallable(name: "fail", description: "Fails."),
        CodemodeCallable(name: "mcp__dev-radius__search", description: "Search.")
    ]

    private func run(_ code: String, limits: CodemodeLimits = CodemodeLimits()) async -> CodemodeResult {
        await CodemodeKeeper(start: PythonOnPath.start, scripts: CodemodeLimiter(4))
            .run(code, tools: tools, limits: limits) { tool, arguments in
                tool == "fail" ? .failure(CodemodeCallFailure("no such file")) : .success("\(tool) \(arguments)")
            }
    }

    private func text(_ items: String...) -> [CodemodeItem] { items.map { CodemodeItem(text: $0) } }

    @Test func `it awaits a tool called by keyword and returns what it made of it`() async {
        let result = await run("a = await tools.read(path=\"x\")\nreturn len(a)")
        #expect(result == CodemodeResult(items: text("18")))
    }

    @Test func `text is said in order, print is the console, and the return comes last`() async {
        let result = await run(
            #"text("one"); text({"a": [1, 2]}); text(3); print("seen", 1); print("no newline", end=""); return ["done"]"#
        )
        let expected = [
            CodemodeItem(text: "one"), CodemodeItem(text: #"{"a": [1, 2]}"#), CodemodeItem(text: "3"),
            CodemodeItem(text: "seen 1", console: true), CodemodeItem(text: "no newline", console: true),
            CodemodeItem(text: #"["done"]"#)
        ]
        #expect(result == CodemodeResult(items: expected))
    }

    @Test func `many calls run at once with gather, and nothing returned adds nothing`() async {
        let result = await run("all = await asyncio.gather(*[tools.read(i=i) for i in range(50)])\ntext(len(all))")
        #expect(result == CodemodeResult(items: text("50")))
        #expect(await run("x = 1") == CodemodeResult())
    }

    @Test func `a tool is called by its name, its identifier or with one dict, and ALL_TOOLS lists them`() async {
        let result = await run(
            """
            a = await tools.mcp__dev_radius__search(q=1)
            b = await tools["mcp__dev-radius__search"]()
            c = await tools.read({"path": "y"})
            return [a, b, c, [t["name"] for t in ALL_TOOLS]]
            """
        )
        let expected =
            #"["mcp__dev-radius__search {\"q\": 1}", "mcp__dev-radius__search {}", "read {\"path\": \"y\"}", "#
            + #"["read", "fail", "mcp__dev_radius__search"]]"#
        #expect(result == CodemodeResult(items: text(expected)))
    }

    @Test func `a tool that fails raises ToolError with its words, and uncaught it fails the script on its line`() async
    {
        let caught = await run("try:\n    await tools.fail()\nexcept ToolError as e:\n    return str(e)")
        #expect(caught == CodemodeResult(items: text("no such file")))
        let uncaught = await run("text(\"before\")\nawait tools.fail()")
        #expect(uncaught == CodemodeResult(items: text("before"), failure: "ToolError: no such file (codemode.py:2)"))
    }

    @Test(arguments: [
        ("a = 1\nb = {}\nreturn b[\"missing\"]", "KeyError: 'missing' (codemode.py:3)"),
        ("a = await tools.read()\nreturn (", "SyntaxError: '(' was never closed (codemode.py:2)"),
        ("return await tools.nope()", "AttributeError: No tool is named nope; ALL_TOOLS lists them. (codemode.py:1)"),
        (
            "return await tools.read(\"x\")",
            "TypeError: read takes its arguments by keyword, or as one dict (codemode.py:1)"
        ),
        ("import sys\nsys.exit(3)", "SystemExit: 3"),
        ("import numpy", "ModuleNotFoundError: No module named 'numpy' (codemode.py:1)")
    ])
    func `a script that fails says what, and on which of its lines`(code: String, failure: String) async {
        let result = await run(code)
        // Python's words for a syntax error differ between its versions; the line and the kind do not.
        if failure.hasPrefix("SyntaxError") {
            #expect(
                result.failure?.hasPrefix("SyntaxError: ") == true
                    && result.failure?.hasSuffix("(codemode.py:2)") == true
            )
        } else {
            #expect(result.failure == failure)
        }
    }

    @Test func `exit ends it successfully with what it had said, and calls it did not wait for are counted`() async {
        #expect(await run("text(\"kept\"); exit(); text(\"never\")") == CodemodeResult(items: text("kept")))
        #expect(await run("tools.read(); tools.read(); return 1") == CodemodeResult(items: text("1"), unsettled: 2))
    }

    @Test func `output past what may be held fails the script, whatever it catches`() async {
        let result = await run(
            "try:\n    while True: text(\"x\" * (1 << 16))\nexcept BaseException:\n    text(\"caught\")\nreturn \"done\""
        )
        #expect(
            result.failure
                == "The script said more than 1048576 characters; write large data to a file with a tool instead."
        )
        #expect(result.items.count == 16)
        let many = await run("try:\n    while True: print()\nexcept BaseException:\n    pass")
        #expect(many.failure == "The script made more than 10000 text and print calls.")
        #expect(many.items.count == 10_000)
    }

    @Test func `the most a script may say comes back whole, however it is escaped on the way`() async {
        let result = await run("text(\"\\x01\" * \(CodemodeVM.maximumCharacters - 3))\nreturn \"end\"")
        #expect(result.failure == nil && result.items.count == 2)
        #expect(result.items.first?.text.utf16.count == CodemodeVM.maximumCharacters - 3)
    }

    @Test(arguments: [
        "open(\"/etc/passwd\").read()", "import os\nos.listdir(\"/private/etc\")",
        "import os\nos.listdir(\"/Users\")", "open(\"/tmp/ask-python-escaped.txt\", \"w\").write(\"x\")",
        "import socket\nsocket.create_connection((\"1.1.1.1\", 80), 2)",
        "import socket\nsocket.socket().bind((\"127.0.0.1\", 0))",
        "import subprocess\nsubprocess.run([\"/bin/ls\", \"/\"])", "import os\nos.fork()", "import os\nos.getcwd()",
        "import os\nos.kill(os.getppid(), 0)"
    ])
    func `it can open no file, reach no network, start no program and signal nobody`(attempt: String) async {
        let result = await run(
            "try:\n    " + attempt.replacing("\n", with: "\n    ")
                + "\n    return \"REACHED\"\nexcept OSError as e:\n    return type(e).__name__"
        )
        #expect(result == CodemodeResult(items: text("PermissionError")), "\(attempt)")
        #expect(!FileManager.default.fileExists(atPath: "/tmp/ask-python-escaped.txt"))
    }

    @Test func `it has no environment, and its standard library still computes`() async {
        let result = await run(
            """
            import os, re, json, math, statistics, datetime, hashlib, difflib, collections, itertools, textwrap, base64, zlib
            return [dict(os.environ), statistics.mean([1, 2, 3]), hashlib.sha256(b"x").hexdigest()[:8], datetime.date.today().year > 2000]
            """
        )
        #expect(result == CodemodeResult(items: text(#"[{}, 2, "2d711642", true]"#)))
    }

    /// The deadline is short on purpose: should the watch ever be lost, the script is stopped before it has taken the machine.
    /// One allocation larger than the limit holds the interpreter's lock while it is filled, so the script's own watch sees it
    /// only once made. That watch is given a limit it never reaches here: only the keeper's, from outside, can stop the script.
    @Test func `one allocation larger than the limit is stopped by the keeper, from outside the process`() async {
        let start: CodemodeChild.Start = { _ in await PythonOnPath.start(1 << 20) }
        let result = await CodemodeKeeper(start: start, scripts: CodemodeLimiter(1))
            .run(
                "text(\"before\")\nawait tools.read(path=\"x\")\nbig = [0] * (1 << 27)\nreturn len(big)",
                tools: tools,
                limits: CodemodeLimits(deadline: .seconds(30), memoryMiB: 96)
            ) { _, _ in .success("") }
        #expect(result.failure == "The script took more than 96 MiB of memory and was stopped.")
        #expect(result.items == text("before"))
    }

    @Test func `a script that allocates without end is stopped at its memory, and keeps what it had said`() async {
        let result = await run(
            "text(\"before\")\nprint(\"a line\")\nbig = []\nwhile True: big.append([0] * (1 << 16))",
            limits: CodemodeLimits(deadline: .seconds(3), memoryMiB: 96)
        )
        #expect(result.failure == "The script took more than 96 MiB of memory and was stopped.")
        #expect(result.items == [CodemodeItem(text: "before"), CodemodeItem(text: "a line", console: true)])
    }

    @Test func `a script that spins is stopped at its deadline`() async {
        let result = await run("while True: pass", limits: CodemodeLimits(deadline: .milliseconds(600)))
        #expect(result.failure?.hasPrefix("The script ran past its deadline of 0.6 s and was stopped.") == true)
    }
}
