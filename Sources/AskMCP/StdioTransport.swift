internal import Foundation
internal import Subprocess
internal import Synchronization
internal import System

/// A server that is a child process, spoken to on its standard input and output (ADR-0096).
///
/// One JSON-RPC message a line, in both directions; the child's standard error is not part of the conversation and is kept, a bit of it,
/// for saying why a server went away. The child leads a session of its own, so closing it reaches everything it started: end of
/// input first, which is how a well-behaved server is told to leave, then after a grace the polite signal to the whole group, then the
/// other one.
public final class StdioTransport: MCPTransport {
    /// How the child ended.
    public enum Exit: Sendable, Equatable {
        case exited(Int)
        case signalled(Int)
    }

    /// The most of a server's standard error that is kept, from its end.
    static let standardErrorBytes = 4096

    /// What the run learned, set once it ends.
    struct Outcome {
        /// The process id once it has started, and whether it did: nil until known.
        var pid: Int32?
        var launched: Bool?
        var exit: Exit?
        var failure: String?
        var standardError: [UInt8] = []
    }

    public let incoming: AsyncStream<[UInt8]>
    private let outboundSink: AsyncStream<[UInt8]>.Continuation
    private let shared: Shared
    private let run: Task<Void, Never>
    private let clock: any Clock<Duration>
    private let grace: Duration
    private let maximumMessageBytes: Int

    /// Starts the child at once.
    /// - Parameters:
    ///   - launch: what to run.
    ///   - clock: what the grace is measured on.
    ///   - grace: how long a closed server has to leave on its own before it is stopped.
    ///   - maximumMessageBytes: the longest message a server may send; a longer one ends the conversation.
    ///   - observer: told when the process starts and ends.
    public init(
        _ launch: StdioLaunch, clock: any Clock<Duration> = ContinuousClock(), grace: Duration = .seconds(2),
        maximumMessageBytes: Int = 64 << 20, observer: (any StdioProcessObserver)? = nil
    ) {
        self.maximumMessageBytes = maximumMessageBytes
        self.clock = clock
        self.grace = grace
        let (incoming, incomingSink) = AsyncStream.makeStream(of: [UInt8].self)
        let (outbound, outboundSink) = AsyncStream.makeStream(of: [UInt8].self)
        self.incoming = incoming
        self.outboundSink = outboundSink
        let shared = Shared(incoming: incomingSink, observer: observer)
        self.shared = shared
        run = Task {
            await Self.drive(launch, outbound: outbound, shared: shared, maximumMessageBytes: maximumMessageBytes)
        }
    }

    /// Returns once the child has started or has failed to.
    /// - Returns: its process id, or nil if the program could not be started.
    public func waitUntilRunning() async -> Int32? {
        await withCheckedContinuation { continuation in
            let known = shared.waiting.withLock { waiters -> Bool in
                if shared.outcome.withLock({ $0.launched != nil }) { return true }
                waiters.append(continuation)
                return false
            }
            if known { continuation.resume() }
        }
        return shared.outcome.withLock { $0.pid }
    }

    /// How the child ended, once it has.
    public var exit: Exit? { shared.outcome.withLock { $0.exit } }

    /// Why the run failed: the program could not be started, or the server was stopped for what it sent.
    public var failure: String? { shared.outcome.withLock { $0.failure } }

    public var diagnostic: String? {
        if let failure { return failure }
        let lastLine = standardErrorTail.split(whereSeparator: \.isNewline).last.map(String.init)
        return lastLine.flatMap { $0.isEmpty ? nil : $0 }
    }

    /// The last few kilobytes the child wrote to standard error.
    public var standardErrorTail: String {
        shared.outcome.withLock { String(decoding: $0.standardError, as: UTF8.self) }
    }

    public func send(_ message: [UInt8]) async throws {
        if case .terminated = outboundSink.yield(message + [0x0A]) { throw CancellationError() }
    }

    public func close() async {
        outboundSink.finish()
        // A server that was told to leave has the grace to do it; after that it is stopped, which is what cancelling the run does.
        let stopper = Task { [run, clock, grace] in
            guard (try? await clock.sleep(for: grace)) != nil else { return }
            run.cancel()
        }
        await run.value
        stopper.cancel()
    }
}
