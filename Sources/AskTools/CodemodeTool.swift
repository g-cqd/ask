internal import AemiJSON
public import AskAI
public import AskAgentCore
internal import AskCodemode
internal import Foundation

/// `codemode` (ADR-0156, after pi's): the model writes one JavaScript script that calls the run's other tools, in parallel and
/// in chains, and filters what they return, so that one compact result reaches the context in place of many.
///
/// The script runs in a process of its own (`ask codemode`), where the only thing it can reach is the tools; each call it makes
/// comes back here and goes through the loop (``NestedTools``): the hooks and the sandbox apply as to a direct call. The person
/// is asked about the script once, as a whole, before it runs (``ApprovalPolicy``).
public struct CodemodeTool: ArgumentTool {
    public struct Arguments: Decodable, Sendable {
        let code: String
    }

    public let definition = ToolDefinition(
        name: "codemode",
        description: """
            Run one JavaScript script that calls the other tools, instead of calling them one at a time. Use it for independent calls \
            at once (Promise.all), for chains where one result feeds the next, and to filter large results down to what matters \
            before they reach you. The script is the body of an async function: use top-level await and return. Call a tool as \
            `await tools.<name>({...})` with the arguments of a direct call; it resolves to the tool's text and rejects with an Error \
            when the call fails. `text(value)` adds output, `console.log` is kept apart, the returned value comes last; `ALL_TOOLS` \
            lists what can be called. Nothing else exists: no files, network, timers or modules, everything goes through tools. \
            A first line `// @options: {"timeout_ms": 60000, "max_output_tokens": 2000}` changes the limits (120 s, 10000 tokens). \
            Calls made before a failure are not undone.
            """
    ) {
        ToolProperty.string("code", minLength: 1)
    }

    private let keeper: CodemodeKeeper
    private let clock: any Clock<Duration>

    /// The tool, running each script in a child `executable codemode`: ask itself.
    public init(executable: String) {
        keeper = CodemodeKeeper(start: CodemodeChild.process(executable))
        clock = ContinuousClock()
    }

    init(start: @escaping CodemodeChild.Start, scripts: CodemodeLimiter, clock: any Clock<Duration> = ContinuousClock())
    {
        keeper = CodemodeKeeper(start: start, scripts: scripts)
        self.clock = clock
    }

    public func run(_ arguments: Arguments, in context: ToolContext) async throws(ToolFailure) -> ToolOutput {
        guard let nested = context.nested else {
            throw ToolFailure("codemode runs inside a turn of the conversation, where there are tools to call.")
        }
        let limits = try CodemodeLimits.parse(arguments.code).get()
        let callable = nested.definitions()
            .map { CodemodeCallable(name: $0.name, description: Self.brief($0.description)) }
        var result = CodemodeResult()
        let took = await clock.measure {
            result = await keeper.run(arguments.code, tools: callable, limits: limits) { tool, arguments in
                guard let input = try? JSONObject(validating: Array(arguments.utf8)) else {
                    return .failure(
                        CodemodeCallFailure("The arguments of \(tool) must be an object, as for a direct call.")
                    )
                }
                let output = await nested.call(tool, input)
                return output.isError ? .failure(CodemodeCallFailure(output.content)) : .success(output.content)
            } called: { began, ended in
                context.reportProgress("\(ended) of \(began) call\(began == 1 ? "" : "s") done")
            }
        }
        let report = CodemodeReport.text(result, took: took)
        return ToolOutput(Self.fitted(report, to: limits, in: context), isError: result.failure != nil)
    }

    /// `report` within the tokens the script may return; what does not fit is written whole beside the session's other outputs.
    private static func fitted(_ report: String, to limits: CodemodeLimits, in context: ToolContext) -> String {
        guard CodemodeReport.fitted(report, tokens: limits.outputTokens, whole: nil) != report else { return report }
        let file = context.outputDirectory.flatMap { directory -> String? in
            let path = directory + "/codemode-\(context.callID ?? UUID().uuidString).txt"
            // try?: the model is told where the whole output is only when it was written; without the file it gets the cut one
            try? FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
            // try?: the model is told where the whole output is only when it was written; without the file it gets the cut one
            return (try? Data(report.utf8).write(to: URL(fileURLWithPath: path))) == nil ? nil : path
        }
        return CodemodeReport.fitted(report, tokens: limits.outputTokens, whole: file)
    }

    /// What a tool is for, in a line: the first line of its description, at most 200 characters. The model has each tool's
    /// whole description already; a script's `ALL_TOOLS` is for finding a name.
    static func brief(_ description: String) -> String {
        let line = description.prefix { !$0.isNewline }
        return line.count > 200 ? line.prefix(199) + "…" : String(line)
    }
}
