internal import AskAgentCore
internal import Synchronization

/// A decision left for the screen (idea i1): how this run's sessions are kept is asked once the screen is up, and a first prompt waits
/// for it before its session is made.
extension SessionKeyAccess {
    private enum Pending {
        case none
        case waiting([CheckedContinuation<Bool, Never>])
        /// The person wanted encryption and the keys could not be opened: nothing may be written.
        case refused
    }

    private static let pending = Mutex(Pending.none)

    /// Leaves the decision for ``settle(_:)``.
    static func leavePending() { pending.withLock { $0 = .waiting([]) } }

    static var isPending: Bool {
        pending.withLock {
            if case .waiting = $0 { return true }
            return false
        }
    }

    /// Decides, unless something decided first (`/encrypt` while the question was open), and lets waiting prompts go. `overriding`
    /// decides whatever came before: the person's own `/encrypt`.
    static func settle(_ protection: SessionProtection, overriding: Bool = false) {
        let waiters = pending.withLock { state -> [CheckedContinuation<Bool, Never>] in
            var waiters: [CheckedContinuation<Bool, Never>] = []
            if case .waiting(let waiting) = state {
                waiters = waiting
            } else if !overriding {
                return []
            }
            state = .none
            decide(protection)
            return waiters
        }
        for waiter in waiters { waiter.resume(returning: true) }
    }

    /// No session may be written in this run.
    static func refuse() {
        let waiters = pending.withLock { state -> [CheckedContinuation<Bool, Never>] in
            guard case .waiting(let waiters) = state else { return [] }
            state = .refused
            return waiters
        }
        for waiter in waiters { waiter.resume(returning: false) }
    }

    /// Returns once the decision is made; throws when it was refused.
    static func settled() async throws {
        let ready = await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
            let now: Bool? = pending.withLock { state in
                switch state {
                    case .none: return true
                    case .refused: return false
                    case .waiting(let waiters):
                        state = .waiting(waiters + [continuation])
                        return nil
                }
            }
            if let now { continuation.resume(returning: now) }
        }
        guard ready else { throw SessionProtectionSetup.Refusal.cannotUnlock }
    }
}
