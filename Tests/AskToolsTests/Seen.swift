import Synchronization

/// What a transport factory was asked for, remembered so a test can look at it afterwards.
final class Seen: Sendable {
    private let state = Mutex<(called: Bool, environment: [String: String], headers: [String: String])>(
        (false, [:], [:]))

    func set(_ environment: [String: String], _ headers: [String: String]) {
        state.withLock { $0 = (true, environment, headers) }
    }

    var wasCalled: Bool { state.withLock { $0.called } }
    var environment: [String: String] { state.withLock { $0.environment } }
    var headers: [String: String] { state.withLock { $0.headers } }
}
