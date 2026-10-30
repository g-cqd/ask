internal import Network
internal import Synchronization

/// The system's route to the network, through `NWPathMonitor` (Network framework), which says when the Mac goes offline and when it is
/// back, without polling (roadmap 0141). A monitor is made only when a request has failed, and cancelled once it has answered.
public struct SystemNetworkPath: NetworkPath {
    public init() {}

    public func isSatisfied() async -> Bool { await first(waitingForRoute: false, limit: .seconds(2)) ?? true }

    public func waitUntilSatisfied(atMost limit: Duration) async -> Bool {
        await first(waitingForRoute: true, limit: limit) ?? false
    }

    /// The path's first answer, or with `waitingForRoute` the first satisfied one; nil after `limit` or when cancelled.
    private func first(waitingForRoute: Bool, limit: Duration) async -> Bool? {
        let monitor = NWPathMonitor()
        let answer = Answer()
        defer { monitor.cancel() }
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                answer.hold(continuation)
                monitor.pathUpdateHandler = { path in
                    let satisfied = path.status == .satisfied
                    if satisfied || !waitingForRoute { answer.give(satisfied) }
                }
                monitor.start(queue: .global(qos: .utility))
                Task {
                    try? await Task.sleep(for: limit)
                    answer.give(nil)
                }
                if Task.isCancelled { answer.give(nil) }
            }
        } onCancel: {
            answer.give(nil)
        }
    }

    /// The one answer a wait returns, from whichever comes first: the path, the limit, or a cancellation.
    private final class Answer: Sendable {
        private let continuation = Mutex<CheckedContinuation<Bool?, Never>?>(nil)

        func hold(_ held: CheckedContinuation<Bool?, Never>) { continuation.withLock { $0 = held } }

        func give(_ value: Bool?) { continuation.withLock { $0.take() }?.resume(returning: value) }
    }
}
