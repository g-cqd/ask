public import AemiIO
internal import Darwin
public import System

/// A session backed by an append-only file.
///
/// - Every change appends one complete record and is flushed per ``Durability`` before it is committed in
///   memory. A change that fails to persist is not applied.
/// - Opening never writes, even to a damaged file (ADR-0013). The repairs listed in ``issues`` exist in
///   memory until the first change.
/// - The first change after a damaged open writes a fresh, complete file and keeps the original under
///   `<name>.damaged` (then `-2`, `-3`, …), by hard link and atomic rename. At every instant a complete
///   session file exists, and damaged bytes are never discarded. Appending instead would glue the new record
///   onto a torn fragment and corrupt it.
/// - A failed append marks the file for the same rewrite, so a half-written record is never appended to.
/// - It is the session's only writer: creating and opening take an exclusive lock that is held until the file
///   closes, and carried over to the replacement file across a rewrite (``SessionLock``, ADR-0024).
///
/// `~Copyable`, so the descriptor has exactly one owner and closes when it does.
public struct SessionFile: ~Copyable {
    /// How far a record must travel before a change counts as committed: AemiIO's profile (ADR-0017).
    ///
    /// `.barrier`, the default, is what recovery needs. A crash leaves a prefix of the log and at most a torn
    /// tail, which ``SessionLog/recover(_:limits:)`` repairs losslessly. Plain `fsync` lets the drive reorder
    /// writes, which can leave a hole mid-log or a renamed repair whose bytes never landed. `.full` adds
    /// "on disk when the call returns", at about 2.6 ms per change, more than the action budget. `.none`
    /// survives a crash of `ask` only.
    public typealias Durability = DurabilityProfile

    /// Where the session lives.
    public let path: FilePath
    /// The session: always what replaying the file yields, after any pending repair.
    public private(set) var tree: SessionTree
    /// Repairs made when the file was opened. Empty for an undamaged file.
    public let issues: [SessionLogIssue]
    /// The flush applied to every change.
    public let durability: Durability
    private var appender: FileDescriptor?
    private var lock: SessionLock
    private var needsRewrite: Bool
    private let writeRecord: RecordWriter

    /// Writes one record to the append descriptor. Only tests replace it, to make that write fail.
    typealias RecordWriter = ([UInt8], FileDescriptor) throws(SessionFileError) -> Void

    /// Internal for the opening extension only; sessions are made by ``create(at:durability:)`` and ``open(at:durability:limits:)``.
    init(
        path: FilePath, tree: SessionTree, issues: [SessionLogIssue], durability: Durability,
        appender: FileDescriptor?, lock: consuming SessionLock,
        writeRecord: @escaping RecordWriter = SessionFileIO.writeAll
    ) {
        self.lock = lock
        self.writeRecord = writeRecord
        self.path = path
        self.tree = tree
        self.issues = issues
        self.durability = durability
        self.appender = appender
        self.needsRewrite = !issues.isEmpty
    }

    deinit {
        if let appender { _ = try? appender.close() }
    }

    // MARK: - Changes

    /// Appends under the leaf and persists it. A change that cannot be persisted is undone.
    /// - Returns: the new entry's identifier.
    /// - Throws: ``SessionFileError/tree(_:)`` for an invalid change, with nothing written, or an I/O error.
    /// - Complexity: O(1) amortized, plus the flush. Holding a copy of ``tree`` across a change makes that
    ///   change copy the whole tree, so read it when needed rather than keeping it.
    @discardableResult
    public mutating func append(_ payload: SessionPayload) throws(SessionFileError) -> EntryID {
        let checkpoint = tree.checkpoint
        let id: EntryID
        do { id = try tree.append(payload) } catch { throw .tree(error) }
        try persistEntry(id, undoingTo: checkpoint)
        return id
    }

    /// Appends under an earlier entry and persists it. A change that cannot be persisted is undone.
    /// - Returns: the new entry's identifier.
    /// - Throws: ``SessionFileError/tree(_:)`` for an invalid change, with nothing written, or an I/O error.
    @discardableResult
    public mutating func continuing(
        from parent: EntryID, with payload: SessionPayload
    ) throws(SessionFileError) -> EntryID {
        let checkpoint = tree.checkpoint
        let id: EntryID
        do { id = try tree.continuing(from: parent, with: payload) } catch { throw .tree(error) }
        try persistEntry(id, undoingTo: checkpoint)
        return id
    }

    /// Selects an entry, or nil for a new root, and persists the checkout. Undone if it cannot be persisted.
    /// - Throws: ``SessionFileError/tree(_:)`` for an unknown entry, with nothing written, or an I/O error.
    public mutating func moveLeaf(to id: EntryID?) throws(SessionFileError) {
        let checkpoint = tree.checkpoint
        do { try tree.moveLeaf(to: id) } catch { throw .tree(error) }
        do throws(SessionFileError) {
            try persist(try SessionFileIO.encoded { () throws(SessionLogError) in try SessionLog.line(forLeaf: id) })
        } catch {
            tree.rewind(to: checkpoint)
            throw error
        }
    }

    /// Records the strict sandbox the session now runs under, and persists it. Undone if it cannot be persisted.
    /// - Throws: an I/O error; the session keeps the sandbox it had.
    public mutating func recordSandbox(_ section: SandboxSection) throws(SessionFileError) {
        let checkpoint = tree.checkpoint
        let record = section.strict
        tree.recordSandbox(record)
        do throws(SessionFileError) {
            try persist(
                try SessionFileIO.encoded { () throws(SessionLogError) in try SessionLog.line(forSandbox: record) })
        } catch {
            tree.rewind(to: checkpoint)
            throw error
        }
    }

    // MARK: - Persistence

    private mutating func persistEntry(_ id: EntryID, undoingTo checkpoint: SessionTree.Checkpoint)
        throws(SessionFileError)
    {
        do throws(SessionFileError) {
            guard let entry = tree.entry(id) else { throw .tree(.unknownEntry(id)) }
            try persist(try SessionFileIO.encoded { () throws(SessionLogError) in try SessionLog.line(for: entry) })
        } catch {
            tree.rewind(to: checkpoint)
            throw error
        }
    }

    /// Persists the change already applied to ``tree``: `record` is appended, or, when a rewrite is
    /// pending, the whole tree is written beside the file and swapped in.
    private mutating func persist(_ record: [UInt8]) throws(SessionFileError) {
        if needsRewrite {
            try rewrite()
            return
        }
        let descriptor = try openAppender()
        do {
            try writeRecord(record, descriptor)
            try SessionFileIO.flush(descriptor, durability)
        } catch {
            // Part of the record may be on disk. Never append after it; rewrite from memory next time.
            needsRewrite = true
            throw error
        }
    }

    private mutating func openAppender() throws(SessionFileError) -> FileDescriptor {
        if let appender { return appender }
        let descriptor = try SessionFileIO.io(.open) {
            try FileDescriptor.open(path, .writeOnly, options: [.append])
        }
        appender = descriptor
        return descriptor
    }

    /// Writes ``tree`` beside the file, keeps the current file as a damaged copy, then swaps atomically.
    private mutating func rewrite() throws(SessionFileError) {
        let temporary = FilePath(path.string + ".tmp")
        let snapshot = try SessionFileIO.encoded { () throws(SessionLogError) in try SessionLog.snapshot(tree) }
        let descriptor = try SessionFileIO.io(.open) {
            try FileDescriptor.open(
                temporary, .writeOnly, options: [.create, .truncate], permissions: [.ownerReadWrite])
        }
        do {
            try SessionFileIO.writeAll(snapshot, to: descriptor)
            try SessionFileIO.flush(descriptor, durability)
        } catch {
            _ = try? descriptor.close()
            throw error
        }
        // The replacement is locked before it takes the session's name, so the name is never unlocked.
        let replacementLock = try SessionLock.adopt(descriptor)
        try preserveDamagedOriginal()
        guard rename(temporary.string, path.string) == 0 else { throw .io(.rename, errno: errno) }
        lock = replacementLock
        try SessionFileIO.flushDirectory(of: path, durability)
        if let appender { _ = try? appender.close() }
        appender = nil
        needsRewrite = false
    }

    /// Hard-links the current file to the first free `<name>.damaged[-n]`. Nothing to keep if it is gone.
    private func preserveDamagedOriginal() throws(SessionFileError) {
        for attempt in 1 ... 1_000 {
            let suffix = attempt == 1 ? ".damaged" : ".damaged-\(attempt)"
            if link(path.string, path.string + suffix) == 0 { return }
            switch errno {
                case EEXIST: continue
                case ENOENT: return
                default: throw .io(.link, errno: errno)
            }
        }
        throw .io(.link, errno: EEXIST)
    }
}
