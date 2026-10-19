internal import Synchronization

/// The context window a server showed it has, learned during a run and kept for the loop's later runs.
///
/// When a reply stops because the window filled, its prompt, cached and output tokens add up to the window exactly
/// (diary 14: 6,353 + 696 + 1,143 = 8,192 on an 8k llama.cpp server). Shared by reference, so an interactive
/// conversation that reuses one loop keeps what it learned. Only ever shrinks: a smaller observation is the binding one.
final class LearnedWindow: Sendable {
    private let tokens = Mutex<Int?>(nil)

    /// The smallest window observed, if any.
    var window: Int? { tokens.withLock { $0 } }

    /// Records that the window held at most `observed` tokens.
    func learn(_ observed: Int) {
        guard observed > 0 else { return }
        tokens.withLock { $0 = Swift.min($0 ?? observed, observed) }
    }
}
