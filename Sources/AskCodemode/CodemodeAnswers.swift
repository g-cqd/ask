internal import Foundation
internal import Synchronization

/// The answers to a script's calls, on their way from the tasks that got them to the one thread the script runs on: put from
/// anywhere, taken by that thread, which sleeps until there is one.
final class CodemodeAnswers: Sendable {
    typealias Answer = (call: Int, outcome: Result<String, CodemodeCallFailure>)

    private let waiting = Mutex<[Answer]>([])
    private let arrived = DispatchSemaphore(value: 0)

    func put(_ call: Int, _ outcome: Result<String, CodemodeCallFailure>) {
        waiting.withLock { $0.append((call, outcome)) }
        arrived.signal()
    }

    /// Every answer that has come, in the order they came; sleeps until there is at least one.
    func take() -> [Answer] {
        arrived.wait()
        return waiting.withLock { answers in
            defer { answers = [] }
            return answers
        }
    }
}
