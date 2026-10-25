internal import Synchronization

@testable import AskMCP

/// Remembers what a stdio transport told it, in order.
final class RecordingObserver: StdioProcessObserver {
    private let state = Mutex<(started: [Int32], ended: [Int32])>(([], []))

    var started: [Int32] { state.withLock { $0.started } }
    var ended: [Int32] { state.withLock { $0.ended } }

    func started(group: Int32) { state.withLock { $0.started.append(group) } }
    func ended(group: Int32) { state.withLock { $0.ended.append(group) } }
}
