internal import Synchronization
internal import System

/// The one owner of an open session file, shareable with the task that runs the loop.
///
/// A run is its own task so that abort can cancel it, and that task needs the session by reference: an `inout`
/// borrow cannot cross into it. Appends happen under the lock; readers get a copy of the tree.
public final class SessionRecorder: Sendable {
    private let file: Mutex<SessionFile>

    /// Takes ownership of `file`.
    public init(_ file: consuming sending SessionFile) { self.file = Mutex(file) }

    /// Appends `payload` and persists it before returning.
    /// - Throws: whatever the file throws; nothing is recorded then.
    @discardableResult
    public func append(_ payload: SessionPayload) throws(SessionFileError) -> EntryID {
        try file.withLock { (file: inout SessionFile) throws(SessionFileError) -> EntryID in try file.append(payload) }
    }

    /// Reads the session under the lock without copying it out: a copy alive at the next append would make
    /// that append copy the whole tree.
    /// - Parameter body: reads the tree.
    /// - Returns: what `body` returns.
    func reading<Result: Sendable>(_ body: (borrowing SessionTree) -> Result) -> Result {
        file.withLock { body($0.tree) }
    }

    /// The session as recorded so far.
    public var tree: SessionTree { file.withLock { $0.tree } }

    /// Where the session lives.
    public var path: String { file.withLock { $0.path.string } }
}
