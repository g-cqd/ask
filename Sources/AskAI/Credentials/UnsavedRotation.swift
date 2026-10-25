internal import Synchronization

/// Credentials the server has rotated that could not be written to the file yet (roadmap 0056, ADR-0082).
///
/// A refresh token is single use: once the server has accepted it, the copy in the file is spent and the replacement exists only in
/// the response. If the save then fails (the save lock held too long, a full disk), dropping the response signs the user out for a
/// failure that was only transient. So the replacement is kept here, shared by every copy of the accessor that holds this box, used
/// for requests and refreshes while the file cannot take it, and saved on the next call.
final class UnsavedRotation<Credentials: Sendable & Equatable>: Sendable {
    /// What is held: the credentials the server will accept, and what the file still holds, which it will not.
    struct Held: Sendable {
        let current: Credentials
        let stored: Credentials
        /// Why the file could not take it, as it would be said to a person.
        let reason: String
    }

    private let held = Mutex<Held?>(nil)

    /// What is held, if anything.
    var value: Held? { held.withLock { $0 } }

    /// Holds `current`, which replaces `stored` as soon as the file can take it.
    func hold(_ current: Credentials, replacing stored: Credentials, because reason: String) {
        held.withLock { $0 = Held(current: current, stored: stored, reason: reason) }
    }

    /// Lets go: the replacement was saved, or the user changed what is stored and what they did stands.
    func clear() { held.withLock { $0 = nil } }
}
