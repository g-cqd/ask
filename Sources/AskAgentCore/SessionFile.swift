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
///
/// `~Copyable`, so the descriptor has exactly one owner and closes when it does.
public struct SessionFile: ~Copyable {
    /// How far a record must travel before a change counts as committed.
    ///
    /// Measured on this machine's APFS volume, per 484-byte record: `write` 2 µs, `fsync` 25 µs median,
    /// `F_FULLFSYNC` 2.9 ms median and 14 ms worst. Only the first two fit the 2 ms action budget.
    public enum Durability: Sendable, Equatable {
        /// In the kernel's cache: survives a crash of `ask`, not of the OS.
        case process
        /// `fsync`: survives an OS crash. The default.
        case system
        /// `F_FULLFSYNC`: survives power loss. Costs milliseconds per change.
        case device
    }

    /// Where the session lives.
    public let path: FilePath
    /// The session, always equal to what replaying the file yields (after any pending repair).
    public private(set) var tree: SessionTree
    /// Repairs made when the file was opened. Empty for an undamaged file.
    public let issues: [SessionLogIssue]
    private let durability: Durability
    private var appender: FileDescriptor?
    private var needsRewrite: Bool
    private let writeRecord: RecordWriter

    /// Writes one record to the append descriptor. Only tests replace it, to make that write fail.
    typealias RecordWriter = ([UInt8], FileDescriptor) throws(SessionFileError) -> Void

    private init(
        path: FilePath, tree: SessionTree, issues: [SessionLogIssue], durability: Durability,
        appender: FileDescriptor?, writeRecord: @escaping RecordWriter = SessionFileIO.writeAll
    ) {
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

    // MARK: - Creating and opening

    /// Creates an empty session at `path`. Never overwrites.
    /// - Parameters:
    ///   - path: the new file.
    ///   - durability: the flush applied to every change.
    /// - Returns: the open session.
    /// - Throws: ``SessionFileError/alreadyExists``, or an I/O error, after removing any partial file.
    public static func create(
        at path: FilePath, durability: Durability = .system
    ) throws(SessionFileError) -> SessionFile {
        let empty = SessionTree()
        let descriptor = try SessionFileIO.writeExclusively(
            try SessionFileIO.encoded { () throws(SessionLogError) in try SessionLog.snapshot(empty) },
            to: path, durability: durability)
        return SessionFile(path: path, tree: empty, issues: [], durability: durability, appender: descriptor)
    }

    /// Opens a session, repairing damage in memory. Never writes.
    /// - Parameters:
    ///   - path: the session file.
    ///   - durability: the flush applied to every later change.
    ///   - limits: the size ceilings, checked before the file is read.
    /// - Returns: the session, with ``issues`` describing any repair.
    /// - Throws: an I/O error, or ``SessionLogError/archiveTooLarge(_:)`` and
    ///   ``SessionLogError/unsupportedVersion(_:)`` as ``SessionFileError/log(_:)``.
    public static func open(
        at path: FilePath, durability: Durability = .system, limits: SessionLog.Limits = .standard
    ) throws(SessionFileError) -> SessionFile {
        try open(at: path, durability: durability, limits: limits, writeRecord: SessionFileIO.writeAll)
    }

    /// ``open(at:durability:limits:)`` with the record write replaced, so tests can fail it.
    static func open(
        at path: FilePath, durability: Durability = .system, limits: SessionLog.Limits = .standard,
        writeRecord: @escaping RecordWriter
    ) throws(SessionFileError) -> SessionFile {
        let bytes = try SessionFileIO.readAll(path, limits: limits)
        let recovered: RecoveredSession
        do {
            recovered = try SessionLog.recover(bytes, limits: limits)
        } catch {
            throw .log(error)
        }
        return SessionFile(
            path: path, tree: recovered.tree, issues: recovered.issues, durability: durability, appender: nil,
            writeRecord: writeRecord)
    }

    // MARK: - Changes

    /// Appends under the leaf, persists it, then commits it.
    /// - Returns: the new entry's identifier.
    /// - Throws: ``SessionFileError/tree(_:)`` for an invalid change, with nothing written, or an I/O error.
    @discardableResult
    public mutating func append(_ payload: SessionPayload) throws(SessionFileError) -> EntryID {
        var next = tree
        let id: EntryID
        do { id = try next.append(payload) } catch { throw .tree(error) }
        try commitEntry(id, in: next)
        return id
    }

    /// Appends under an earlier entry, persists it, then commits it.
    /// - Returns: the new entry's identifier.
    /// - Throws: ``SessionFileError/tree(_:)`` for an invalid change, with nothing written, or an I/O error.
    @discardableResult
    public mutating func continuing(
        from parent: EntryID, with payload: SessionPayload
    ) throws(SessionFileError) -> EntryID {
        var next = tree
        let id: EntryID
        do { id = try next.continuing(from: parent, with: payload) } catch { throw .tree(error) }
        try commitEntry(id, in: next)
        return id
    }

    /// Selects an entry, or nil for a new root, persists the checkout, then commits it.
    /// - Throws: ``SessionFileError/tree(_:)`` for an unknown entry, with nothing written, or an I/O error.
    public mutating func moveLeaf(to id: EntryID?) throws(SessionFileError) {
        var next = tree
        do { try next.moveLeaf(to: id) } catch { throw .tree(error) }
        try commit(
            next, record: try SessionFileIO.encoded { () throws(SessionLogError) in try SessionLog.line(forLeaf: id) })
    }

    /// Writes the active branch to a new file. Never overwrites.
    /// - Parameter destination: the new file.
    /// - Returns: the forked session, open at `destination`.
    /// - Throws: ``SessionFileError/alreadyExists`` or an I/O error.
    public borrowing func fork(to destination: FilePath) throws(SessionFileError) -> SessionFile {
        let forked: SessionTree
        do { forked = try tree.fork() } catch { throw .tree(error) }
        let descriptor = try SessionFileIO.writeExclusively(
            try SessionFileIO.encoded { () throws(SessionLogError) in try SessionLog.snapshot(forked) },
            to: destination, durability: durability)
        return SessionFile(
            path: destination, tree: forked, issues: [], durability: durability, appender: descriptor)
    }

    // MARK: - Persistence

    private mutating func commitEntry(_ id: EntryID, in next: SessionTree) throws(SessionFileError) {
        guard let entry = next.entry(id) else { throw .tree(.unknownEntry(id)) }
        try commit(
            next, record: try SessionFileIO.encoded { () throws(SessionLogError) in try SessionLog.line(for: entry) })
    }

    /// Persists `record` (or a full rewrite when one is pending) and only then adopts `next`.
    private mutating func commit(_ next: SessionTree, record: [UInt8]) throws(SessionFileError) {
        if needsRewrite {
            try rewrite(with: next)
            tree = next
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
        tree = next
    }

    private mutating func openAppender() throws(SessionFileError) -> FileDescriptor {
        if let appender { return appender }
        let descriptor = try SessionFileIO.io(.open) {
            try FileDescriptor.open(path, .writeOnly, options: [.append])
        }
        appender = descriptor
        return descriptor
    }

    /// Writes `next` beside the file, keeps the current file as a damaged copy, then swaps atomically.
    private mutating func rewrite(with next: SessionTree) throws(SessionFileError) {
        let temporary = FilePath(path.string + ".tmp")
        let snapshot = try SessionFileIO.encoded { () throws(SessionLogError) in try SessionLog.snapshot(next) }
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
        _ = try? descriptor.close()
        try preserveDamagedOriginal()
        guard rename(temporary.string, path.string) == 0 else { throw .io(.rename, errno: errno) }
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
