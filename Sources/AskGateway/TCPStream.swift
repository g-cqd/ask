internal import Darwin
internal import Foundation
internal import Synchronization

/// A TCP connection as a ``ByteStream``, on plain sockets, as ``ProviderProxy`` serves its tunnels: a dedicated thread reads,
/// blocking, and hands each piece to an `AsyncStream`; a write blocks the one task that sends for a link, bounded by a send timeout,
/// so a peer that stops reading cannot hold it forever.
package final class TCPStream: ByteStream {
    /// Why a connection could not be made.
    package struct Failure: Error, Equatable, CustomStringConvertible {
        package let call: String
        package let code: Int32
        package var description: String { "\(call): \(String(cString: strerror(code)))" }
    }

    private let descriptor: Int32
    private let closed = Atomic<Bool>(false)
    private let pieces: AsyncStream<[UInt8]>

    /// Wraps a connected socket; the stream owns it and closes it.
    package init(descriptor: Int32) {
        self.descriptor = descriptor
        _ = fcntl(descriptor, F_SETFD, FD_CLOEXEC)
        var timeout = timeval(tv_sec: 30, tv_usec: 0)
        _ = setsockopt(descriptor, SOL_SOCKET, SO_SNDTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
        var noSignal: Int32 = 1
        _ = setsockopt(descriptor, SOL_SOCKET, SO_NOSIGPIPE, &noSignal, socklen_t(MemoryLayout<Int32>.size))
        let (stream, continuation) = AsyncStream<[UInt8]>.makeStream()
        pieces = stream
        Thread.detachNewThread {
            var buffer = [UInt8](repeating: 0, count: 65_536)
            while true {
                let count = buffer.withUnsafeMutableBytes { unsafe read(descriptor, $0.baseAddress, $0.count) }
                if count < 0, errno == EINTR { continue }
                guard count > 0 else { break }
                continuation.yield(Array(buffer[..<count]))
            }
            continuation.finish()
        }
    }

    /// Connects to `host:port`, IPv4 or IPv6, by the addresses `host` resolves to, each tried in turn.
    package static func connect(host: String, port: Int) async throws(Failure) -> TCPStream {
        let result = await withCheckedContinuation {
            (continuation: CheckedContinuation<Result<Int32, Failure>, Never>) in
            Thread.detachNewThread { continuation.resume(returning: connectBlocking(host: host, port: port)) }
        }
        return TCPStream(descriptor: try result.get())
    }

    package func send(_ bytes: [UInt8]) async throws {
        var offset = 0
        while offset < bytes.count {
            let written = bytes[offset...].withUnsafeBytes { unsafe write(descriptor, $0.baseAddress, $0.count) }
            if written < 0, errno == EINTR { continue }
            guard written > 0 else { throw Failure(call: "write", code: errno) }
            offset += written
        }
    }

    /// One task receives at a time, as a link does: each call reads the stream's one buffer through an iterator of its own.
    package func receive() async throws -> [UInt8]? {
        var iterator = pieces.makeAsyncIterator()
        return await iterator.next()
    }

    package func close() async { shut() }

    deinit { shut() }

    /// Ends both directions, which wakes the reading thread, then closes the socket once.
    private func shut() {
        guard !closed.exchange(true, ordering: .relaxed) else { return }
        _ = shutdown(descriptor, SHUT_RDWR)
        Darwin.close(descriptor)
    }

    private static func connectBlocking(host: String, port: Int) -> Result<Int32, Failure> {
        var hints = addrinfo()
        hints.ai_socktype = SOCK_STREAM
        hints.ai_family = AF_UNSPEC
        var list: UnsafeMutablePointer<addrinfo>?
        let status = getaddrinfo(host, String(port), &hints, &list)
        guard status == 0, let first = list else { return .failure(Failure(call: "getaddrinfo", code: EHOSTUNREACH)) }
        defer { freeaddrinfo(first) }
        var last = Failure(call: "connect", code: EHOSTUNREACH)
        var entry: UnsafeMutablePointer<addrinfo>? = first
        while let current = entry {
            let info = unsafe current.pointee
            let socket = Darwin.socket(info.ai_family, info.ai_socktype, info.ai_protocol)
            if socket >= 0 {
                if unsafe Darwin.connect(socket, info.ai_addr, info.ai_addrlen) == 0 { return .success(socket) }
                last = Failure(call: "connect", code: errno)
                Darwin.close(socket)
            }
            entry = info.ai_next
        }
        return .failure(last)
    }
}
