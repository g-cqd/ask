internal import AemiIO
internal import AemiJSON
internal import Darwin
internal import Foundation
internal import Synchronization
internal import System

/// A list's file (ADR-0140): one record per change, in the session's format (JSONL, or ADR-0138's framed file under a data key of
/// its own), the list rebuilt by replaying them. A torn or unreadable record is dropped, and the next change writes the file again from
/// the changes that read. Each change is made under a lock beside the file, after reading what another process appended since, so a list
/// a workspace's sessions share stays one list.
final class ChangeLog<List: ChangeList>: Sendable {
    static var largest: Int { 16 << 20 }
    let path: String
    let keyring: SessionKeyring?
    private let state: Mutex<State>

    /// What was read: the list, the changes that make it, and how the file stands.
    struct State: ~Copyable {
        var list = List()
        var changes: [List.Change] = []
        var format: SessionFormat
        var fileKey: FileKey?
        var framer: FramedWriter?
        /// The file's size when it was last read or written; another size means another process wrote to it.
        var knownSize = 0
        /// Whether every record read cleanly, so a change can be appended rather than the file written again.
        var clean = true
        /// A record kind a later ask wrote: the list is shown without it and never written (ADR-0141).
        var newerKind: String?
    }

    /// The list at `path`, or an empty one kept in `format` when there is no file yet.
    init(path: String, format: SessionFormat, keyring: SessionKeyring?) throws {
        self.path = path
        self.keyring = keyring
        state = Mutex(try Self.read(path, format: format, keyring: keyring))
    }

    var list: List { state.withLock { $0.list } }

    /// The list as the file now holds it, read again if another process changed it.
    func current() throws -> List {
        try withFileLock {
            try state.withLock { (state) throws in
                try refresh(&state)
                return state.list
            }
        }
    }

    /// Makes the change `make` returns for the current list, and keeps it; a refused change writes nothing.
    @discardableResult
    func change(_ make: (List) -> List.Change) throws -> List {
        try update { list in (make(list), ()) }.list
    }

    /// Plans on the current list, read again under the lock: `make` returns the change to keep, or none when nothing is to change, and
    /// what to answer. A thrown plan writes nothing; neither does a list a later ask wrote (``ListRecordError``).
    func update<Answer: Sendable>(
        _ make: (List) throws -> (change: List.Change?, answer: Answer)
    ) throws -> (list: List, answer: Answer) {
        try withFileLock {
            try state.withLock { (state) throws in
                try refresh(&state)
                let (change, answer) = try make(state.list)
                guard let change else { return (state.list, answer) }
                if let kind = state.newerKind { throw ListRecordError(kind: kind) }
                var next = state.list
                try next.apply(change)
                if state.clean, state.knownSize > 0, let record = try record(change, &state) {
                    try append(record)
                } else {
                    try rewrite(state.changes + [change], &state)
                }
                state.changes.append(change)
                state.list = next
                state.knownSize = Self.size(of: path)
                return (next, answer)
            }
        }
    }

    /// The file written again in `format`, as `/encrypt` changes its session's.
    func convert(to format: SessionFormat) throws {
        try withFileLock {
            try state.withLock { (state) throws in
                try refresh(&state)
                guard format != state.format, !state.changes.isEmpty else {
                    state.format = format
                    return
                }
                state.format = format
                state.fileKey = nil
                try rewrite(state.changes, &state)
                state.knownSize = Self.size(of: path)
            }
        }
    }

    private func refresh(_ state: inout State) throws {
        guard Self.size(of: path) != state.knownSize else { return }
        state = try Self.read(path, format: state.format, keyring: keyring)
    }

    /// `change` as the bytes that append it: a JSON line, or a frame; nil when it must be written with the whole file.
    private func record(_ change: List.Change, _ state: inout State) throws -> [UInt8]? {
        let json = try AemiJSON.JSONEncoder().encodeToBytes(change)
        guard state.format.isFramed else { return json + [0x0A] }
        // In place: the framer cannot be copied. No framer is nil: the whole file is written instead.
        do { return try state.framer?.append(json) } catch { throw SessionLogReader.sessionError(error) }
    }

    private func append(_ bytes: [UInt8]) throws {
        let descriptor = try FileDescriptor.open(
            FilePath(path),
            .writeOnly,
            options: [.append, .create],
            permissions: [.ownerReadWrite]
        )
        defer { try? descriptor.close() }
        try SessionFileIO.writeAll(bytes, to: descriptor)
        try SessionFileIO.flush(descriptor, .barrier)
    }

    /// The whole file again, from `changes`: beside it, flushed, then renamed over it.
    private func rewrite(_ changes: [List.Change], _ state: inout State) throws {
        if state.format.encrypted, state.fileKey == nil {
            guard let keyring else { throw SessionFileError.locked }
            state.fileKey = try keyring.newFileKey()
        }
        var lines: [UInt8] = []
        for change in changes { lines += try AemiJSON.JSONEncoder().encodeToBytes(change) + [0x0A] }
        var encoded = try SessionFile.encode(lines, format: state.format, fileKey: state.fileKey)
        let temporary = FilePath(path + ".tmp")
        let descriptor = try FileDescriptor.open(
            temporary,
            .writeOnly,
            options: [.create, .truncate],
            permissions: [.ownerReadWrite]
        )
        do {
            try SessionFileIO.writeAll(encoded.bytes, to: descriptor)
            try SessionFileIO.flush(descriptor, .barrier)
            try descriptor.close()
        } catch {
            try? descriptor.close()
            throw error
        }
        guard rename(temporary.string, path) == 0 else { throw SessionFileError.io(.rename, errno: errno) }
        state.framer = encoded.framer.take()
        state.clean = true
    }

    /// Runs `body` holding an exclusive lock on `<path>.lock`, which outlives the renames a rewrite makes.
    private func withFileLock<Result>(_ body: () throws -> Result) throws -> Result {
        let descriptor = open(path + ".lock", O_RDWR | O_CREAT | O_CLOEXEC, 0o600)
        guard descriptor >= 0 else { throw SessionFileError.io(.lock, errno: errno) }
        defer { close(descriptor) }
        guard flock(descriptor, LOCK_EX) == 0 else { throw SessionFileError.io(.lock, errno: errno) }
        return try body()
    }

    static func size(of path: String) -> Int {
        var status = stat()
        return stat(path, &status) == 0 ? Int(status.st_size) : 0
    }
}

/// The task list's file.
typealias TaskLog = ChangeLog<TaskList>
