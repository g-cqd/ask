import Synchronization

@testable import AskAgentCore

/// A network path played by the test: whether a route is there at each failure, and whether it comes back when waited for.
final class FakeNetworkPath: NetworkPath {
    private let state: Mutex<(online: [Bool], comesBack: Bool, waits: [Duration])>

    /// - Parameters:
    ///   - online: what each check answers in turn; the last answer repeats.
    ///   - comesBack: whether a wait ends with the network back, or at its limit without it.
    init(online: [Bool], comesBack: Bool = true) { state = Mutex((online, comesBack, [])) }

    /// The limit of each wait asked for.
    var waits: [Duration] { state.withLock { $0.waits } }

    func isSatisfied() async -> Bool {
        state.withLock { state in state.online.count > 1 ? state.online.removeFirst() : state.online.first ?? true }
    }

    func waitUntilSatisfied(atMost limit: Duration) async -> Bool {
        state.withLock { state in
            state.waits.append(limit)
            return state.comesBack
        }
    }
}
