internal import AemiJSONRPC
internal import Darwin
internal import Synchronization
internal import System

/// A file descriptor a connection writes its messages to: standard output, when an editor runs ask. One whole message at a time,
/// so two writers never interleave their bytes, and written before the call returns, so what is sent in an order arrives in it.
/// The descriptor is neither owned nor closed.
///
/// A client that has gone no longer reads. Writing to it is then an error the writer is given, where the system's default is
/// a signal that ends the process, with what ask left running for the client still running (diary 2026-11-15-15).
final class DescriptorSink: JSONRPCSink {
    private let descriptor: Mutex<FileDescriptor>

    init(_ descriptor: FileDescriptor) {
        _ = fcntl(descriptor.rawValue, F_SETNOSIGPIPE, 1)
        self.descriptor = Mutex(descriptor)
    }

    func write(_ bytes: [UInt8]) async throws {
        try descriptor.withLock { descriptor in _ = try descriptor.writeAll(bytes) }
    }
}
