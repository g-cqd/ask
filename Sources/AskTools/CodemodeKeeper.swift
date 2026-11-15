internal import AemiJSON
internal import AemiJSONRPC
internal import AskCodemode

/// Keeps one script's process (ADR-0156): starts it, gives it the script, runs the tools it asks for, and holds it to its
/// limits. A script past its deadline, past its memory, or whose process is gone is a failure that says which.
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
        let connection = JSONRPCConnection(serving: CodemodeChildSink(child), framing: .lines) { calls.admit($0) }
        let (chunks, feed) = AsyncThrowingStream<[UInt8], any Error>.makeStream()
        let reading = Task {
            for await line in child.incoming { feed.yield(line + [0x0A]) }
            feed.finish()
        }
        // The calls a script makes run as children of this task: ending it is what cancels those still running.
        let serving = Task { await connection.run(reading: chunks) }
        let parameters = CodemodeWire.runParameters(code: code, tools: tools)
        let result: CodemodeResult
        do {
            let answer = try await connection.request(CodemodeWire.run, parameters, timeout: limits.deadline)
            result =
                CodemodeWire.result(from: answer) ?? CodemodeResult(failure: "The script's result could not be read.")
            await Self.end(child, serving, reading)
        } catch {
            serving.cancel()
            reading.cancel()
            result = CodemodeResult(failure: Self.reason(error, exit: await child.close(), limits))
        }
        return result
    }

    @discardableResult
    private static func end(_ child: CodemodeChild, _ serving: Task<Void, Never>, _ reading: Task<Void, Never>) async
        -> Int32?
    {
        serving.cancel()
        reading.cancel()
        return await child.close()
    }

    /// Why a script got no result, in words for the model. What it had said is lost with its process.
    private static func reason(_ error: any Error, exit: Int32?, _ limits: CodemodeLimits) -> String {
        if exit == CodemodeHost.memoryExit {
            return
                "The script took more than \(limits.memoryMiB) MiB of memory and was stopped. What it had said is lost."
        }
        switch error {
            case JSONRPCConnectionError.timedOut:
                let seconds =
                    Double(limits.deadline.components.seconds) + Double(limits.deadline.components.attoseconds) / 1e18
                let said = seconds == seconds.rounded() ? "\(Int(seconds))" : "\(seconds)"
                return "The script ran past its deadline of \(said) s and was stopped. What it had said is lost. "
                    + #"A first line `// @options: {"timeout_ms": …}` allows up to 600000."#
            case JSONRPCConnectionError.response(let refused): return refused.message
            case is CancellationError: return "The script was stopped."
            default:
                let status = exit.map { " (exit \($0))" } ?? ""
                return "The process that ran the script ended before it answered\(status). What it had said is lost."
        }
    }
}
