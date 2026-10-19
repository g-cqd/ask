internal import Darwin
internal import System

/// The one-writer guarantee for a session file: an exclusive `flock` on its inode, held while the
/// ``SessionFile`` is open (ADR-0024).
///
/// - The kernel releases it when the holder exits, however it exits, so a crashed `ask` leaves no stale lock.
/// - It belongs to the inode, not the name. A rewrite locks its replacement before renaming it into place,
///   so the path is never unlocked in between. A lock taken on a file that has since been replaced guards
///   nothing; comparing inodes detects that, and the lock is taken again.
struct SessionLock: ~Copyable {
    /// Open on the locked file, read-only: opening reads the session through it rather than opening it twice.
    let descriptor: FileDescriptor

    private init(_ descriptor: FileDescriptor) { self.descriptor = descriptor }

    deinit { _ = try? descriptor.close() }

    /// Takes the lock on the file at `path`, without waiting.
    /// - Parameter path: the session file.
    /// - Returns: the held lock.
    /// - Throws: ``SessionFileError/inUse`` when another writer holds it, or an I/O error.
    static func acquire(_ path: FilePath) throws(SessionFileError) -> SessionLock {
        // Each retry means another writer swapped the file between our open and our lock. That writer holds
        // the new file, so the next attempt fails as in use; the bound only stops a pathological loop.
        for _ in 0 ..< 8 {
            let descriptor = try SessionFileIO.io(.open) { try FileDescriptor.open(path, .readOnly) }
            let current: Bool
            do { current = try lock(descriptor, guarding: path) } catch {
                _ = try? descriptor.close()
                throw error
            }
            if current { return SessionLock(descriptor) }
            _ = try? descriptor.close()
        }
        throw .inUse
    }

    /// Holds the lock on a file no other process can know of yet: one just created exclusively, or a
    /// rewrite's replacement before it is renamed into place.
    /// - Parameter descriptor: the file; the lock owns it from here, and closes it.
    /// - Returns: the held lock.
    /// - Throws: ``SessionFileError/inUse`` if another process found the file first, or an I/O error.
    static func adopt(_ descriptor: FileDescriptor) throws(SessionFileError) -> SessionLock {
        guard flock(descriptor.rawValue, LOCK_EX | LOCK_NB) == 0 else {
            let failure = errno
            _ = try? descriptor.close()
            throw failure == EWOULDBLOCK ? .inUse : .io(.lock, errno: failure)
        }
        return SessionLock(descriptor)
    }

    /// Locks `descriptor` without waiting, and says whether it is still the file at `path`.
    /// - Parameters:
    ///   - descriptor: a descriptor opened on `path`.
    ///   - path: the session file.
    /// - Returns: false when `path` names another file now, so the lock just taken guards nothing.
    /// - Throws: ``SessionFileError/inUse`` when another writer holds it, or an I/O error.
    static func lock(_ descriptor: FileDescriptor, guarding path: FilePath) throws(SessionFileError) -> Bool {
        guard flock(descriptor.rawValue, LOCK_EX | LOCK_NB) == 0 else {
            throw errno == EWOULDBLOCK ? .inUse : .io(.lock, errno: errno)
        }
        var held = stat()
        var named = stat()
        guard fstat(descriptor.rawValue, &held) == 0 else { throw .io(.lock, errno: errno) }
        guard stat(path.string, &named) == 0 else { return false }
        return held.st_dev == named.st_dev && held.st_ino == named.st_ino
    }
}
