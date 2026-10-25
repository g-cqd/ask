internal import Synchronization

/// Decides when a person is told that a sign-in the server rotated could not be saved (roadmap 0056, ADR-0082, ADR-0091).
///
/// The accessors keep going without being told, which is right for the request and wrong for the person: if ask is closed before a
/// later request saves it, the next run is signed out with nothing to explain it. So it is said once when it happens, not on every
/// request while it lasts, and said again if it happens again after a save worked.
public final class RotationNotice: Sendable {
    private let provider: String
    private let said = Mutex(false)

    /// A notice about `provider`'s sign-in, as the person knows it ("Claude", "Codex").
    public init(provider: String) { self.provider = provider }

    /// What to tell the person now, if anything.
    /// - Parameter reason: why the save failed, or nil when nothing is unsaved.
    /// - Returns: the notice the first time a failure is seen, nil while the same one goes on or when there is none.
    public func message(unsavedBecause reason: String?) -> String? {
        let first = said.withLock { said -> Bool in
            defer { said = reason != nil }
            return reason != nil && !said
        }
        guard first, let reason else { return nil }
        return
            "Your \(provider) sign-in was refreshed but could not be saved (\(reason)). ask keeps it in memory and tries to save "
            + "it again on the next request; if you quit first, you will need to sign in again."
    }
}
