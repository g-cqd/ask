internal import AemiIO
internal import Darwin
internal import System

/// The system calls behind ``SessionFile``: exclusive creation, whole writes, and flushes (reads are ``SessionLogReader``'s).
/// Policy (when to rewrite, what to keep) stays in `SessionFile`; this type only talks to the kernel.
enum SessionFileIO {
    static func writeExclusively(
        _ bytes: [UInt8], to path: FilePath, durability: SessionFile.Durability
    ) throws(SessionFileError) -> FileDescriptor {
        let descriptor: FileDescriptor
        do {
            descriptor = try FileDescriptor.open(
                path, .writeOnly, options: [.create, .exclusiveCreate, .append], permissions: [.ownerReadWrite])
        } catch let error as Errno where error == .fileExists {
            throw .alreadyExists
        } catch let error as Errno {
            throw .io(.open, errno: error.rawValue)
        } catch {
            throw .io(.open, errno: -1)
        }
        do {
            try writeAll(bytes, to: descriptor)
            try flush(descriptor, durability)
            try flushDirectory(of: path, durability)
        } catch {
            _ = try? descriptor.close()
            unlink(path.string)
            throw error
        }
        return descriptor
    }

    static func writeAll(_ bytes: [UInt8], to descriptor: FileDescriptor) throws(SessionFileError) {
        _ = try io(.write) { try descriptor.writeAll(bytes) }
    }

    static func flush(_ descriptor: FileDescriptor, _ durability: SessionFile.Durability) throws(SessionFileError) {
        guard durability != .none else { return }
        do {
            try PosixFile(borrowing: descriptor.rawValue).sync(durability)
        } catch {
            throw .io(.flush, errno: error.errno)
        }
    }

    /// Makes a create or rename durable: the directory entry must reach disk too.
    static func flushDirectory(of path: FilePath, _ durability: SessionFile.Durability) throws(SessionFileError) {
        guard durability != .none else { return }
        let directory = try io(.open) { try FileDescriptor.open(path.removingLastComponent(), .readOnly) }
        defer { _ = try? directory.close() }
        try flush(directory, durability)
    }

    static func encoded(_ body: () throws(SessionLogError) -> [UInt8]) throws(SessionFileError) -> [UInt8] {
        do { return try body() } catch { throw .log(error) }
    }

    static func io<T>(_ operation: SessionFileError.Operation, _ body: () throws -> T) throws(SessionFileError)
        -> T
    {
        do {
            return try body()
        } catch let error as Errno {
            throw .io(operation, errno: error.rawValue)
        } catch {
            throw .io(operation, errno: -1)
        }
    }
}
