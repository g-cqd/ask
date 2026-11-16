internal import AemiJSON
internal import AemiJSONRPC
internal import AskCodemode
internal import Synchronization

/// Keeps one script's process (ADR-0156): starts it, gives it the script, runs the tools it asks for, keeps what it says, and
/// holds it to its limits. A script past its deadline, past its memory, or whose process is gone is a failure that says which,
/// with what it had said until then.
struct CodemodeKeeper: Sendable {
    /// The scripts running in this process: two at once, the others wait (pi's number).
    static let scripts = CodemodeLimiter(2)

    let start: CodemodeChild.Start
    var scripts = CodemodeKeeper.scripts

    /// Runs `code`, which may call `tools`, each call answered by `call`: what it came to. `called` is told, as calls begin
    /// and end, how many began and how many ended.
    func run(
        _ code: String,
        tools: [CodemodeCallable],
        limits: CodemodeLimits,
        call: @escaping CodemodeVM.Caller,
        called: @escaping @Sendable (_ began: Int, _ ended: Int) -> Void = { _, _ in }
    ) async -> CodemodeResult {
        guard await scripts.acquire() else { return CodemodeResult(failure: "The script was stopped before it began.") }
        defer { scripts.release() }
        guard let child = await start(limits.memoryMiB) else {
            return CodemodeResult(failure: "ask could not start the process that runs a script.")
        }
        let calls = CodemodeCalls(limit: limits.callsInFlight, call: call, called: called)
        let said = CodemodeSaid()
        let (chunks, feed) = AsyncThrowingStream<[UInt8], any Error>.makeStream()
        // Why the keeper itself ended the script, when it did: the first reason, and the child is read no further.
        let stopped = Mutex<String?>(nil)
        let stop: @Sendable (String) -> Void = { why in
            stopped.withLock { $0 = $0 ?? why }
            feed.finish()
        }
        let connection = JSONRPCConnection(serving: CodemodeChildSink(child), framing: .lines) {
            calls.admit($0)
        } onNotification: {
            if !said.take($0) { stop(Self.saidTooMuch) }
        }
        let reading = Task {
            for await line in child.incoming {
                // A line longer than the connection takes would be dropped by it, and what it carried with it, without a word.
                guard line.count < LineFraming.defaultMaximumLineLength else { return stop(Self.tooLarge) }
                feed.yield(line + [0x0A])
            }
            feed.finish()
        }
        // The watch ends the process and no more: what the script had written is still read, to the end of its output.
        let watch = child.memory.map { memory in
            CodemodeWatch(memory, limit: limits.memoryMiB << 20) {
                stopped.withLock { $0 = $0 ?? Self.tookMemory(limits) }
            }
        }
        // The calls a script makes run as children of this task: ending it is what cancels those still running.
        let serving = Task { await connection.run(reading: chunks) }
        let parameters = CodemodeWire.runParameters(code: code, tools: tools)
        var result: CodemodeResult
        do {
            let answer = try await connection.request(CodemodeWire.run, parameters, timeout: limits.deadline)
            result =
                CodemodeWire.result(from: answer) ?? CodemodeResult(failure: "The script's result could not be read.")
            await Self.end(child, serving, reading, watch)
        } catch {
            let exit = await Self.end(child, serving, reading, watch)
            result = CodemodeResult(failure: stopped.withLock { $0 } ?? Self.reason(error, exit: exit, limits))
        }
        // Whatever ended it, what it had said by then is kept.
        result.items = said.items
        return result
    }

    private static let tooLarge =
        "The script's result is too large to return. Return less, or write it to a file with a tool."
    private static let saidTooMuch =
        "The script said more than \(CodemodeVM.maximumCharacters) characters; write large data to a file with a tool instead."

    private static func tookMemory(_ limits: CodemodeLimits) -> String {
        "The script took more than \(limits.memoryMiB) MiB of memory and was stopped."
    }

    /// Ends the watch first: the child's process id is its own only until it is closed.
    @discardableResult
    private static func end(
        _ child: CodemodeChild,
        _ serving: Task<Void, Never>,
        _ reading: Task<Void, Never>,
        _ watch: CodemodeWatch?
    ) async -> Int32? {
        watch?.end()
        serving.cancel()
        reading.cancel()
        return await child.close()
    }

    /// Why a script did not end by itself, in words for the model.
    private static func reason(_ error: any Error, exit: Int32?, _ limits: CodemodeLimits) -> String {
        if exit == CodemodeHost.memoryExit { return tookMemory(limits) }
        switch error {
            case JSONRPCConnectionError.timedOut:
                let seconds =
                    Double(limits.deadline.components.seconds) + Double(limits.deadline.components.attoseconds) / 1e18
                let said = seconds == seconds.rounded() ? "\(Int(seconds))" : "\(seconds)"
                return "The script ran past its deadline of \(said) s and was stopped. "
                    + #"A first line `// @options: {"timeout_ms": …}` allows up to 600000."#
            case JSONRPCConnectionError.response(let refused): return refused.message
            case is CancellationError: return "The script was stopped."
            default:
                let status = exit.map { " (exit \($0))" } ?? ""
                return "The process that ran the script ended before it answered\(status)."
        }
    }
}
