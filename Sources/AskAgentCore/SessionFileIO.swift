internal import Darwin
internal import System

/// The system calls behind ``SessionFile``: exclusive creation, bounded reads, whole writes, and flushes.
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

    static func readAll(_ path: FilePath, limits: SessionLog.Limits) throws(SessionFileError) -> [UInt8] {
        let descriptor = try io(.open) { try FileDescriptor.open(path, .readOnly) }
        defer { _ = try? descriptor.close() }
        let size = Int(try io(.read) { try descriptor.seek(offset: 0, from: .end) })
        guard size <= limits.maximumArchiveBytes else { throw .log(.archiveTooLarge(size)) }
        _ = try io(.read) { try descriptor.seek(offset: 0, from: .start) }
        var bytes = [UInt8](repeating: 0, count: size)
        var filled = 0
        while filled < size {
            let count = try io(.read) {
                try bytes.withUnsafeMutableBytes { raw in
                    try descriptor.read(into: UnsafeMutableRawBufferPointer(rebasing: raw[filled...]))
                }
            }
            if count == 0 { break }  // The file shrank while being read; parse what was there.
            filled += count
        }
        bytes.removeLast(size - filled)
        return bytes
    }

    static func writeAll(_ bytes: [UInt8], to descriptor: FileDescriptor) throws(SessionFileError) {
        _ = try io(.write) { try descriptor.writeAll(bytes) }
    }

    static func flush(_ descriptor: FileDescriptor, _ durability: SessionFile.Durability) throws(SessionFileError) {
        let result: Int32
        switch durability {
            case .process: return
            case .system: result = fsync(descriptor.rawValue)
            case .device: result = fcntl(descriptor.rawValue, F_FULLFSYNC)
        }
        guard result == 0 else { throw .io(.flush, errno: errno) }
    }

    /// Makes a create or rename durable: the directory entry must reach disk too.
    static func flushDirectory(of path: FilePath, _ durability: SessionFile.Durability) throws(SessionFileError) {
        guard durability != .process else { return }
        let directory = try io(.open) { try FileDescriptor.open(path.removingLastComponent(), .readOnly) }
        defer { _ = try? directory.close() }
        guard fsync(directory.rawValue) == 0 else { throw .io(.flush, errno: errno) }
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
