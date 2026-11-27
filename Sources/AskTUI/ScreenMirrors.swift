internal import Synchronization
internal import TerminalKitIO

/// Where a running screen can be mirrored from (ADR-0170): it registers here while it runs, and the gateway's viewer host attaches
/// terminals through it. A process runs one screen, so ``process`` is the one place; a test gives its screen a place of its own.
final class ScreenMirrors: Sendable {
    private struct Running {
        let sink: AsyncStream<ScreenEvent>.Continuation
        let screen: ObjectIdentifier
        var next = 1
    }

    /// The process's screen.
    static let process = ScreenMirrors()

    private let running = Mutex<Running?>(nil)

    init() {}

    /// Screen `screen` started: mirrors may attach through `sink`.
    func register(_ sink: AsyncStream<ScreenEvent>.Continuation, screen: ObjectIdentifier) {
        running.withLock { $0 = Running(sink: sink, screen: screen) }
    }

    /// Screen `screen` closed: no mirror may attach to it. A later screen's registration is left alone.
    func unregister(screen: ObjectIdentifier) {
        running.withLock { if $0?.screen == screen { $0 = nil } }
    }

    /// Whether a screen is running to mirror.
    var isRunning: Bool { running.withLock { $0 != nil } }

    /// Attaches a terminal on `connection` to the running screen; its id, or nil when no screen runs or the terminal cannot be used.
    func attach(_ connection: any TerminalConnection) -> Int? {
        let taken = running.withLock { running -> (Int, AsyncStream<ScreenEvent>.Continuation)? in
            guard var current = running else { return nil }
            defer {
                current.next += 1
                running = current
            }
            return (current.next, current.sink)
        }
        guard let (id, sink) = taken, let mirror = try? ScreenMirror(id: id, connection: connection) else { return nil }
        sink.yield(.mirrorAttached(mirror))
        return id
    }

    /// Mirror `id`'s terminal changed size.
    func resized(_ id: Int) { running.withLock { _ = $0?.sink.yield(.mirrorResized(id)) } }

    /// Mirror `id` goes away.
    func detach(_ id: Int) { running.withLock { _ = $0?.sink.yield(.mirrorEnded(id)) } }
}
