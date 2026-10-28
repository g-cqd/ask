import AskAI
import AskMCP

/// `calls` echo calls on `connection`, `concurrency` at a time, each checked for the size it asked for.
func callMany(_ connection: MCPConnection, calls: Int, size: Int, concurrency: Int) async throws -> Duration {
    let arguments = try JSONObject(validating: Payloads.arguments(size: size))
    let workers = Swift.min(concurrency, calls)
    return try await ContinuousClock()
        .measure {
            try await withThrowingTaskGroup(of: Void.self) { group in
                for worker in 0 ..< workers {
                    // The calls are shared out whole: the first `calls % workers` workers make one more.
                    let share = calls / workers + (worker < calls % workers ? 1 : 0)
                    group.addTask {
                        for _ in 0 ..< share {
                            let result = try await connection.callTool("echo", arguments: arguments)
                            guard case .text(let text) = result.content.first, text.utf8.count == size else {
                                throw StressFailure.wrongAnswer
                            }
                        }
                    }
                }
                try await group.waitForAll()
            }
        }
}

enum StressFailure: Error {
    case wrongAnswer
    case serverDidNotStart(String)
}
