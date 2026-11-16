internal import AskAI

/// What the model is told of `codemode`: how a script is written, in the language or the two that can be run here.
extension CodemodeTool {
    /// What a script is for, and what bounds it, whatever it is written in.
    private static let purpose = """
        instead of calling them one at a time. Use it for independent calls at once, for chains where one result feeds the next, \
        and to filter large results down to what matters before they reach you.
        """
    private static let limits = """
        Nothing else exists for a script: no files, network or other programs, everything goes through tools. A first line \
        `// @options: {"timeout_ms": 60000, "max_output_tokens": 2000}` changes the limits (120 s, 10000 tokens). Calls made \
        before a failure are not undone.
        """
    private static let inJavaScript = """
        The script is the body of an async function: use top-level await and return. Call a tool as `await tools.<name>({...})` \
        with the arguments of a direct call; it resolves to the tool's text and rejects with an Error when the call fails; \
        Promise.all runs several at once. `text(value)` adds output, `console.log` is kept apart, the returned value comes last; \
        `ALL_TOOLS` lists what can be called.
        """
    private static let inPython = """
        With `language: "python"` the script is the body of an `async def` instead: `await tools.name(key=value)` (or one dict), \
        `asyncio.gather` for several at once, `ToolError` when a call fails, `text(value)`, `print` kept apart, `return` last, \
        `# @options: {...}` for the limits; the standard library only, and no installed packages.
        """

    /// The definition for a tool that runs JavaScript, and Python too when `python` says there is one to run.
    static func definition(python: Bool) -> ToolDefinition {
        guard python else {
            return ToolDefinition(
                name: "codemode",
                description:
                    "Run one JavaScript script that calls the other tools, \(purpose) \(inJavaScript) \(limits)"
            ) {
                ToolProperty.string("code", minLength: 1)
            }
        }
        return ToolDefinition(
            name: "codemode",
            description: "Run one script that calls the other tools, \(purpose) \(inJavaScript) \(inPython) \(limits)"
        ) {
            ToolProperty.string("code", minLength: 1)
            ToolProperty.schema("language", #"{"type":"string","enum":["javascript","python"]}"#).optional
        }
    }
}
