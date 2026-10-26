/// Work with a time limit.
enum Deadline {
    struct TimedOut: Error, CustomStringConvertible { var description: String { "no answer in time" } }

    /// Runs `work`, giving up after `limit`: the result of whichever of the two finishes first, the other cancelled.
    static func run<T: Sendable>(
        _ limit: Duration, _ work: @escaping @Sendable () async throws -> T
    ) async -> Result<T, any Error> {
        await withTaskGroup(of: Result<T, any Error>.self) { group in
            group.addTask {
                do { return .success(try await work()) } catch { return .failure(error) }
            }
            group.addTask {
                try? await Task.sleep(for: limit)
                return .failure(TimedOut())
            }
            let first = await group.next() ?? .failure(TimedOut())
            group.cancelAll()
            return first
        }
    }
}
