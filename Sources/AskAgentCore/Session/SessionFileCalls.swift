internal import AemiIO
internal import Darwin
internal import System

/// The system calls a ``SessionFile`` makes that a test may replace, to make exactly one of them fail (roadmap 0057's follow-up, ADR-0084).
///
/// A session file's failure handling is the part nobody sees work: a flush that fails after the bytes were written, a rename that
/// fails after the original was preserved, a lock taken by someone else a moment too soon. Each is a call into the kernel, so each has
/// a seam here, and the real call everywhere else.
struct SessionFileCalls {
    /// Writes one record to the append descriptor.
    var writeRecord: SessionFile.RecordWriter = SessionFileIO.writeAll
    /// Makes what was written durable, per the session's durability.
    var flush: @Sendable (FileDescriptor, SessionFile.Durability) throws(SessionFileError) -> Void = SessionFileIO.flush
    /// Renames a file, as `rename(2)`: 0, or -1 with `errno` set.
    var rename: @Sendable (String, String) -> Int32 = { Darwin.rename($0, $1) }
    /// Takes the session lock on a descriptor no other process can know of yet, and owns the descriptor from then on.
    var adopt: @Sendable (FileDescriptor) throws(SessionFileError) -> SessionLock = SessionLock.adopt

    /// The real calls.
    static var system: SessionFileCalls { SessionFileCalls() }
}
