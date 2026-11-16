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
        /// The language the script is written in; JavaScript when it says nothing.
        var language: String?
    }

    public let definition: ToolDefinition

    private let keeper: CodemodeKeeper
    /// What runs a Python script, when there is a Python to run one.
    private let python: CodemodeKeeper?
    private let clock: any Clock<Duration>

    /// The tool, running each JavaScript script in a child `executable codemode` (ask itself), and each Python script on the
    /// first `python3` of `path`, a `PATH`, when there is one (the owner, 2026-11-16).
    public init(executable: String, path: String?) {
        self.init(
            start: CodemodeChild.process(executable),
            python: CodemodePython.first(onPath: path).map(CodemodePython.child),
            scripts: CodemodeKeeper.scripts
        )
    }

    init(
        start: @escaping CodemodeChild.Start,
        python: CodemodeChild.Start? = nil,
        scripts: CodemodeLimiter,
        clock: any Clock<Duration> = ContinuousClock()
    ) {
        keeper = CodemodeKeeper(start: start, scripts: scripts)
        self.python = python.map { CodemodeKeeper(start: $0, scripts: scripts) }
        definition = Self.definition(python: python != nil)
        self.clock = clock
    }

    /// The keeper that runs a script written in `language`.
    private func keeper(for language: String?) throws(ToolFailure) -> CodemodeKeeper {
        guard let language = CodemodeLanguage(rawValue: language ?? CodemodeLanguage.javascript.rawValue) else {
            throw ToolFailure("ask runs scripts in \(CodemodeLanguage.named), not in \(language ?? "that").")
        }
        switch (language, python) {
            case (.javascript, _): return keeper
            case (.python, let python?): return python
            case (.python, nil):
                throw ToolFailure("There is no python3 on the PATH to run a Python script: write it in JavaScript.")
        }
    }

    public func run(_ arguments: Arguments, in context: ToolContext) async throws(ToolFailure) -> ToolOutput {
        guard let nested = context.nested else {
            throw ToolFailure("codemode runs inside a turn of the conversation, where there are tools to call.")
        }
        let keeper = try keeper(for: arguments.language)
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
