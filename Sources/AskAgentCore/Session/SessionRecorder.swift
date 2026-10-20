internal import Synchronization
internal import System

/// The one owner of an open session file, shareable with the task that runs the loop.
///
/// A run is its own task so that abort can cancel it, and that task needs the session by reference: an `inout`
/// borrow cannot cross into it. Appends happen under the lock; readers get a copy of the tree.
public final class SessionRecorder: Sendable {
    private let file: Mutex<SessionFile>
    /// The repairs made when the session was opened. Empty for an undamaged file.
    public let issues: [SessionLogIssue]

    /// Takes ownership of `file`.
    public init(_ file: consuming sending SessionFile) {
        issues = file.issues
        self.file = Mutex(file)
    }

    /// A sentence telling the user what was wrong with the session file and what was done, or nil when nothing was.
    /// The repair is in memory; the original is kept beside the file, as `.damaged`, when the first change is made.
    public var repairNotice: String? {
        guard !issues.isEmpty else { return nil }
        let shown = issues.prefix(3).map(\.explanation)
        let more = issues.count > shown.count ? ", and \(issues.count - shown.count) more" : ""
        let count = issues.count == 1 ? "a problem" : "\(issues.count) problems"
        return "The session file had \(count), repaired as it was opened: " + shown.joined(separator: "; ") + more
            + ". The original is kept as a .damaged copy once anything is added."
    }

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

    /// The strict sandbox the session last recorded, read without copying the tree out.
    public var sandbox: SandboxSection? { file.withLock { $0.tree.sandbox } }

    /// Records the strict sandbox the session now runs under, unless it is already the one recorded.
    /// - Throws: whatever the file throws; nothing is recorded then.
    public func recordSandbox(_ section: SandboxSection) throws(SessionFileError) {
        let record = SandboxSection(write: section.write, network: section.network)
        try file.withLock { (file: inout SessionFile) throws(SessionFileError) in
            guard file.tree.sandbox != record else { return }
            try file.recordSandbox(record)
        }
    }

    /// The session as recorded so far.
    public var tree: SessionTree { file.withLock { $0.tree } }

    /// Where the session lives.
    public var path: String { file.withLock { $0.path.string } }
}
