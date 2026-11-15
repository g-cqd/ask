internal import AemiJSONRPC
internal import Synchronization
internal import System

/// A file descriptor a connection writes its messages to: standard output, when an editor runs ask. One whole message at a time,
/// so two writers never interleave their bytes, and written before the call returns, so what is sent in an order arrives in it.
/// The descriptor is neither owned nor closed.
final class DescriptorSink: JSONRPCSink {
    private let descriptor: Mutex<FileDescriptor>

    init(_ descriptor: FileDescriptor) { self.descriptor = Mutex(descriptor) }

    func write(_ bytes: [UInt8]) async throws {
        try descriptor.withLock { descriptor in _ = try descriptor.writeAll(bytes) }
    }
}
