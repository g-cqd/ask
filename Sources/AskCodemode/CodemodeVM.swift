internal import Foundation
internal import JavaScriptCore

/// One script in one JavaScriptCore context (ADR-0156): the body of an async function whose only way out of the VM is the
/// tools it is handed. A context has no files, network or timers of its own, so nothing is taken away; the surface is added.
///
/// JavaScriptCore runs a script on the thread that calls into it, and calls back on that thread. So a VM lives on one thread
/// made for it: the script runs there, the answers to its calls are brought there (``CodemodeAnswers``), and nothing of
/// JavaScriptCore's is touched from anywhere else. It cannot stop a script that never yields, nor cap its memory, without
/// calls outside Apple's public headers: the process that hosts this is what is stopped (the keeper, in the tools).
package final class CodemodeVM {
    /// Calls `tool` with `arguments` (a JSON object, as text): its text, or why it failed.
    package typealias Caller =
        @Sendable (_ tool: String, _ arguments: String) async -> Result<String, CodemodeCallFailure>

    /// The most a script may say before it fails: held whole until it ends, so bounded (pi's numbers).
    package static let maximumCharacters = 16 << 20
    package static let maximumItems = 100_000

    private let tools: [CodemodeCallable]
    private let call: Caller
    private let answers = CodemodeAnswers()
    private var result = CodemodeResult()
    private var characters = 0
    /// The calls the script waits on, by number: what settles each.
    private var pending: [Int: (resolve: JSValue, reject: JSValue)] = [:]
    private var calls = 0
    private var ended = false

    private init(tools: [CodemodeCallable], call: @escaping Caller) {
        self.tools = tools
        self.call = call
    }

    /// Runs `code` to its end on a thread of its own: what it said, and why it failed if it did. `tools` are what it may call,
    /// each call answered by `call`.
    package static func run(_ code: String, tools: [CodemodeCallable], call: @escaping Caller) async -> CodemodeResult {
        await withCheckedContinuation { finished in
            let thread = Thread { finished.resume(returning: CodemodeVM(tools: tools, call: call).run(code)) }
            // A script may recurse as deep as JavaScriptCore lets it; a secondary thread's half megabyte is little for that.
            thread.stackSize = 4 << 20
            thread.start()
        }
    }

    /// The script, from its first statement to its end, on the calling thread.
    private func run(_ code: String) -> CodemodeResult {
        guard let context = JSContext() else { return CodemodeResult(failure: "JavaScriptCore gave no context.") }
        guard let build = context.evaluateScript(CodemodePrelude.source), !build.isUndefined,
            let runner = build.call(withArguments: [bridge(in: context), tools.map(Self.described)])
        else { return CodemodeResult(failure: "The script's surface could not be built.") }
        // The script's first line shares the wrapper's, so a line in an error is a line of the script.
        let script = context.evaluateScript(
            "(async function () {" + code + "\n})",
            withSourceURL: URL(string: "codemode.js")
        )
        if let thrown = context.exception {
            context.exception = nil
            return CodemodeResult(failure: Self.described(thrown))
        }
        runner.call(withArguments: [script as Any])
        // It has run as far as it can: it has ended, or it waits on calls, or it waits on nothing that can come.
        while !ended {
            guard !pending.isEmpty else {
                end(failure: "The script is waiting on a promise that nothing can settle: no tool call is pending.")
                break
            }
            for answer in answers.take() { settle(answer.call, answer.outcome, in: context) }
        }
        return result
    }

    /// The functions the prelude reaches ask through, each called by JavaScriptCore on this thread.
    private func bridge(in context: JSContext) -> [String: Any] {
        let call: @convention(block) (String, String) -> JSValue? = { [unowned self] tool, arguments in
            self.began(tool, arguments, in: context)
        }
        let emit: @convention(block) (Bool, String) -> Void = { [unowned self] console, text in
            self.said(text, console: console, in: context)
        }
        let finish: @convention(block) () -> Void = { [unowned self] in self.end(failure: nil) }
        let fail: @convention(block) (JSValue) -> Void = { [unowned self] error in
            self.end(failure: Self.described(error))
        }
        return ["call": call, "emit": emit, "exit": finish, "done": finish, "fail": fail]
    }

    /// A call the script made: a promise it may wait on, settled when the tool has answered.
    private func began(_ tool: String, _ arguments: String, in context: JSContext) -> JSValue? {
        // Once the script has ended nothing it does counts: a call is not made, and its promise stays as it is.
        guard !ended else { return JSValue(newPromiseIn: context) { _, _ in } }
        calls += 1
        let number = calls
        let promise = JSValue(newPromiseIn: context) { [unowned self] resolve, reject in
            if let resolve, let reject { self.pending[number] = (resolve, reject) }
        }
        Task { [call, answers] in answers.put(number, await call(tool, arguments)) }
        return promise
    }

    private func settle(_ number: Int, _ outcome: Result<String, CodemodeCallFailure>, in context: JSContext) {
        guard !ended, let waiting = pending.removeValue(forKey: number) else { return }
        switch outcome {
            case .success(let text): waiting.resolve.call(withArguments: [text])
            case .failure(let failure):
                waiting.reject.call(withArguments: [JSValue(newErrorFromMessage: failure.message, in: context) as Any])
        }
    }

    private func said(_ text: String, console: Bool, in context: JSContext) {
        guard !ended else { return }
        let limit: String? =
            if result.items.count >= Self.maximumItems {
                "The script made more than \(Self.maximumItems) text and console calls."
            } else if characters + text.utf16.count > Self.maximumCharacters {
                "The script said more than \(Self.maximumCharacters) characters; write large data to a file with a tool instead."
            } else {
                nil
            }
        if let limit {
            // The script fails whatever it catches: its result is fixed here, and the throw only unwinds it.
            end(failure: limit)
            context.exception = JSValue(newErrorFromMessage: limit, in: context)
            return
        }
        characters += text.utf16.count
        result.items.append(CodemodeItem(text: text, console: console))
    }

    /// Ends the script, once: what it does afterwards is not looked at.
    private func end(failure: String?) {
        guard !ended else { return }
        ended = true
        result.failure = failure
        result.unsettled = pending.count
    }

    /// A tool as the prelude takes it.
    private static func described(_ tool: CodemodeCallable) -> [String: String] {
        ["name": tool.name, "identifier": tool.identifier, "description": tool.description]
    }

    /// What was thrown, as the model reads it: an error's name and message, and the script's line when it has one.
    private static func described(_ thrown: JSValue) -> String {
        let said = thrown.toString() ?? "The script failed."
        guard thrown.isObject, let line = thrown.forProperty("line"), line.isNumber else { return said }
        return "\(said) (codemode.js:\(line.toInt32()))"
    }
}
