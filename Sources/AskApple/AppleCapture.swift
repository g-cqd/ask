internal import Synchronization

/// The one tool call a response made, taken by the tool the framework called so the call can go back to ask's loop instead of being run here.
final class AppleCapture: Sendable {
    struct Call: Sendable, Equatable {
        let id: String
        let name: String
        let arguments: String
    }

    private let held = Mutex<Call?>(nil)

    /// Keeps the first call; a response that makes several is answered one at a time, the loop asking again after the first result.
    func record(_ call: Call) { held.withLock { if $0 == nil { $0 = call } } }

    var call: Call? { held.withLock { $0 } }
}
