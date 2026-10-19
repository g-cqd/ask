public import AemiIO
public import System

/// Creating, opening and forking: every way a ``SessionFile`` comes to own a file, and its lock (ADR-0025).
extension SessionFile {
    /// Creates an empty session at `path`. Never overwrites.
    /// - Parameters:
    ///   - path: the new file.
    ///   - durability: the flush applied to every change.
    /// - Returns: the open session.
    /// - Throws: ``SessionFileError/alreadyExists``, or an I/O error, after removing any partial file.
    ///   ``SessionFileError/inUse`` in the instant race where another `ask` opens the new file first.
    public static func create(
        at path: FilePath, durability: Durability = .barrier
    ) throws(SessionFileError) -> SessionFile {
        try begin(SessionTree(), at: path, durability: durability)
    }

    /// Writes `tree` as a new file at `path`, which must not exist, and opens it for appending.
    static func begin(
        _ tree: SessionTree, at path: FilePath, durability: Durability
    ) throws(SessionFileError) -> SessionFile {
        let descriptor = try SessionFileIO.writeExclusively(
            try SessionFileIO.encoded { () throws(SessionLogError) in try SessionLog.snapshot(tree) },
            to: path, durability: durability)
        let lock = try SessionLock.adopt(try SessionFileIO.io(.lock) { try descriptor.duplicate() })
        return SessionFile(
            path: path, tree: tree, issues: [], durability: durability, appender: descriptor, lock: lock)
    }

    /// Opens a session for writing, repairing damage in memory. Never writes until the first change.
    /// - Parameters:
    ///   - path: the session file.
    ///   - durability: the flush applied to every later change.
    ///   - limits: the size ceilings, checked before the file is read.
    /// - Returns: the session, with ``issues`` describing any repair.
    /// - Throws: ``SessionFileError/inUse`` when another `ask` has it open, an I/O error, or
    ///   ``SessionLogError/archiveTooLarge(_:)`` and
    ///   ``SessionLogError/unsupportedVersion(_:)`` as ``SessionFileError/log(_:)``.
    public static func open(
        at path: FilePath, durability: Durability = .barrier, limits: SessionLog.Limits = .standard
    ) throws(SessionFileError) -> SessionFile {
        try open(at: path, durability: durability, limits: limits, writeRecord: SessionFileIO.writeAll)
    }

    /// ``open(at:durability:limits:)`` with the record write replaced, so tests can fail it.
    static func open(
        at path: FilePath, durability: Durability, limits: SessionLog.Limits = .standard,
        writeRecord: @escaping RecordWriter
    ) throws(SessionFileError) -> SessionFile {
        // Locked before reading, so no other writer can append between what we read and what we write.
        let lock = try SessionLock.acquire(path)
        let bytes = try SessionFileIO.readAll(lock.descriptor, limits: limits)
        let recovered: RecoveredSession
        do {
            recovered = try SessionLog.recover(bytes, limits: limits)
        } catch {
            throw .log(error)
        }
        return SessionFile(
            path: path, tree: recovered.tree, issues: recovered.issues, durability: durability, appender: nil,
            lock: lock, writeRecord: writeRecord)
    }

    /// Writes the active branch to a new file. Never overwrites.
    /// - Parameter destination: the new file.
    /// - Returns: the forked session, open at `destination`.
    /// - Throws: ``SessionFileError/alreadyExists`` or an I/O error.
    public borrowing func fork(to destination: FilePath) throws(SessionFileError) -> SessionFile {
        let forked: SessionTree
        do { forked = try tree.fork() } catch { throw .tree(error) }
        return try Self.begin(forked, at: destination, durability: durability)
    }
}
