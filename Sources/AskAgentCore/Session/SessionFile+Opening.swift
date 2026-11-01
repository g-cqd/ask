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
    /// - Parameters:
    ///   - format: how the file is kept; encrypted needs `keyring`.
    ///   - keyring: the keys a new encrypted file's data key is sealed under.
    public static func create(
        at path: FilePath,
        durability: Durability = .barrier,
        format: SessionFormat = .plain,
        keyring: SessionKeyring? = nil
    ) throws(SessionFileError) -> SessionFile {
        try begin(SessionTree(), at: path, durability: durability, calls: .system, format: format, keyring: keyring)
    }

    /// Writes `tree` as a new file at `path`, which must not exist, and opens it for appending.
    static func begin(
        _ tree: SessionTree,
        at path: FilePath,
        durability: Durability,
        calls: SessionFileCalls,
        format: SessionFormat = .plain,
        keyring: SessionKeyring? = nil
    ) throws(SessionFileError) -> SessionFile {
        var fileKey: FileKey?
        if format.encrypted {
            guard let keyring else { throw .locked }
            do { fileKey = try keyring.newFileKey() } catch { throw .locked }
        }
        var encoded = try encode(
            try SessionFileIO.encoded { () throws(SessionLogError) in
                try SessionLog.snapshot(
                    tree,
                    images: SessionImageStore(
                        besideSessionAt: path.string,
                        key: format.encrypted ? keyring?.imageKey : nil
                    )
                )
            },
            format: format,
            fileKey: fileKey
        )
        let descriptor = try SessionFileIO.writeExclusively(encoded.bytes, to: path, durability: durability)
        let lock: SessionLock
        do {
            lock = try calls.adopt(try SessionFileIO.io(.lock) { try descriptor.duplicate() })
        } catch {
            // The duplicate is closed by whoever failed to adopt it; this descriptor is ours, and nothing else would close it.
            _ = try? descriptor.close()
            throw error
        }
        return SessionFile(
            path: path,
            tree: tree,
            issues: [],
            durability: durability,
            appender: descriptor,
            lock: lock,
            calls: calls,
            storage: SessionStorage(format: format, keyring: keyring, fileKey: fileKey, framer: encoded.framer.take())
        )
    }

    /// Opens a session for writing, repairing damage in memory. Never writes until the first change.
    /// - Parameters:
    ///   - path: the session file.
    ///   - durability: the flush applied to every later change.
    ///   - limits: the size ceilings, checked before the file is read.
    ///   - keyring: the keys an encrypted session opens with; it is ``SessionFileError/locked`` without them.
    /// - Returns: the session, with ``issues`` describing any repair.
    /// - Throws: ``SessionFileError/inUse`` when another `ask` has it open, an I/O error, or
    ///   ``SessionLogError/archiveTooLarge(_:)`` and
    ///   ``SessionLogError/unsupportedVersion(_:)`` as ``SessionFileError/log(_:)``.
    public static func open(
        at path: FilePath,
        durability: Durability = .barrier,
        limits: SessionLog.Limits = .standard,
        keyring: SessionKeyring? = nil
    ) throws(SessionFileError) -> SessionFile {
        try open(at: path, durability: durability, limits: limits, calls: .system, keyring: keyring)
    }

    /// ``open(at:durability:limits:)`` with the record write replaced, so tests can fail it.
    static func open(
        at path: FilePath,
        durability: Durability,
        limits: SessionLog.Limits = .standard,
        writeRecord: @escaping RecordWriter
    ) throws(SessionFileError) -> SessionFile {
        var calls = SessionFileCalls.system
        calls.writeRecord = writeRecord
        return try open(at: path, durability: durability, limits: limits, calls: calls)
    }

    /// ``open(at:durability:limits:)`` with system calls replaced, so tests can fail them.
    static func open(
        at path: FilePath,
        durability: Durability,
        limits: SessionLog.Limits = .standard,
        calls: SessionFileCalls,
        keyring: SessionKeyring? = nil
    ) throws(SessionFileError) -> SessionFile {
        // Locked before reading, so no other writer can append between what we read and what we write.
        let lock = try SessionLock.acquire(path)
        let recovered = try SessionLogReader()
            .recover(
                lock.descriptor,
                limits: limits,
                images: SessionImageStore(besideSessionAt: path.string),
                keyring: keyring
            )
        var storage = SessionStorage(keyring: keyring)
        if let framing = recovered.framing {
            storage.format = SessionFormat(compressed: framing.header.compressed, encrypted: framing.header.encrypted)
            storage.fileKey = framing.fileKey
            // A file read with issues is rewritten at the first change, which makes a writer of its own.
            if recovered.issues.isEmpty {
                storage.framer = try? FramedWriter(
                    continuing: framing.header,
                    after: framing.frameCount,
                    key: framing.fileKey?.key
                )
            }
        }
        return SessionFile(
            path: path,
            tree: recovered.tree,
            issues: recovered.issues,
            durability: durability,
            appender: nil,
            lock: lock,
            calls: calls,
            formatVersion: recovered.formatVersion,
            storage: storage
        )
    }

    /// Writes the active branch to a new file. Never overwrites.
    /// - Parameter destination: the new file.
    /// - Returns: the forked session, open at `destination`.
    /// - Throws: ``SessionFileError/alreadyExists`` or an I/O error.
    public borrowing func fork(to destination: FilePath) throws(SessionFileError) -> SessionFile {
        try fork(upTo: tree.leaf, to: destination)
    }

    /// Writes the branch that ends at `leaf` to a new file, as if the session had been left there. The original is not touched: its
    /// selected entry and its file stay as they were. Never overwrites.
    /// - Parameters:
    ///   - leaf: the last entry to keep, or nil for a session that starts again from nothing.
    ///   - destination: the new file.
    /// - Returns: the forked session, open at `destination`, holding the strict sandbox the original recorded.
    /// - Throws: ``SessionFileError/tree(_:)`` for an unknown entry, ``SessionFileError/alreadyExists``, or an I/O error.
    public borrowing func fork(
        upTo leaf: EntryID?,
        to destination: FilePath
    ) throws(SessionFileError) -> sending SessionFile {
        var branch = tree
        var forked: SessionTree
        do {
            try branch.moveLeaf(to: leaf)
            forked = try branch.fork()
        } catch { throw .tree(error) }
        if let sandbox = tree.sandbox { forked.recordSandbox(sandbox) }
        // The real system calls, not the original's: a fork is a session of its own, kept as the original is, under a data key of its
        // own when encrypted.
        return try Self.begin(
            forked,
            at: destination,
            durability: durability,
            calls: .system,
            format: format,
            keyring: keyring
        )
    }
}
