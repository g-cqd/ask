internal import AemiJSONRPC
internal import Darwin
internal import Synchronization

/// The host's standard output, which carries its messages to the parent: one whole message at a time, so two writers never
/// interleave. A parent that has gone no longer reads; writing to it is then an error, where the default is a signal.
final class CodemodeOutput: JSONRPCSink {
    private let writing = Mutex(())

    init() { _ = fcntl(STDOUT_FILENO, F_SETNOSIGPIPE, 1) }

    func write(_ bytes: [UInt8]) async throws {
        try writing.withLock { _ in
            var sent = 0
            while sent < bytes.count {
                let wrote = bytes[sent...]
                    .withUnsafeBytes { unsafe Darwin.write(STDOUT_FILENO, $0.baseAddress, $0.count) }
                guard wrote > 0 else { throw CodemodeCallFailure("The parent no longer reads (errno \(errno)).") }
                sent += wrote
            }
        }
    }
}
