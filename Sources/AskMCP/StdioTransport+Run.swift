internal import Foundation
internal import Subprocess
internal import Synchronization
internal import System

extension StdioTransport {
    /// What the run needs from the transport, held by the run and not by the transport, so a transport that is let go does not keep it.
    final class Shared: Sendable {
        let outcome = Mutex(Outcome())
        let incoming: AsyncStream<[UInt8]>.Continuation
        let observer: (any StdioProcessObserver)?
        /// Callers of ``StdioTransport/waitUntilRunning()``, resumed once it is known whether the child started.
        let waiting = Mutex<[CheckedContinuation<Void, Never>]>([])

        init(incoming: AsyncStream<[UInt8]>.Continuation, observer: (any StdioProcessObserver)?) {
            self.incoming = incoming
            self.observer = observer
        }

        /// Records whether the child started, and lets the waiters know. The observer is told first, so a waiter that returns can rely on it.
        func launched(_ pid: Int32?) {
            if let pid { observer?.started(group: pid) }
            outcome.withLock {
                $0.pid = pid
                $0.launched = pid != nil
            }
            let resumed = waiting.withLock { waiters -> [CheckedContinuation<Void, Never>] in
                defer { waiters = [] }
                return waiters
            }
            for continuation in resumed { continuation.resume() }
        }
    }

    /// Runs the child to its end: writes what is queued, splits what it prints into messages, keeps a little of what it complains of.
    static func drive(
        _ launch: StdioLaunch, outbound: AsyncStream<[UInt8]>, shared: Shared, maximumMessageBytes: Int
    ) async {
        defer { shared.incoming.finish() }
        do {
            let result = try await Subprocess.run(
                configuration(launch), input: .inputWriter, output: .sequence, error: .sequence
            ) { execution in
                shared.launched(execution.processIdentifier.value)
                let writer = execution.standardInputWriter
                // The writer ends when the transport is closed; the readers end when the child's pipes do. The writer is stopped when the
                // readers are done, because a child that has gone will not take what is queued, and nothing else will end it.
                let writing = Task {
                    for await message in outbound { _ = try? await writer.write(message) }
                    try? await writer.finish()
                }
                let complaints = Task {
                    do {
                        for try await buffer in execution.standardError {
                            let bytes = buffer.withUnsafeBytes { Array($0) }
                            shared.outcome.withLock { outcome in
                                outcome.standardError = Array(
                                    (outcome.standardError + bytes).suffix(standardErrorBytes))
                            }
                        }
                    } catch {}
                }
                do {
                    try await read(execution.standardOutput, into: shared, limit: maximumMessageBytes)
                } catch {
                    // A server that sends what no message is the size of is stopped: leaving the body is what stops it.
                    complaints.cancel()
                    writing.cancel()
                    throw error
                }
                await complaints.value
                writing.cancel()
                await writing.value
            }
            let exit: Exit =
                switch result.terminationStatus {
                    case .exited(let code): .exited(Int(code))
                    case .signaled(let signal): .signalled(Int(signal))
                }
            shared.outcome.withLock { $0.exit = exit }
            if let pid = shared.outcome.withLock({ $0.pid }) { shared.observer?.ended(group: pid) }
        } catch {
            shared.outcome.withLock { $0.failure = String(describing: error) }
            // Whatever ended it, the waiters learn that it is over; and a child that did start is still to be released.
            if let pid = shared.outcome.withLock({ $0.pid }) { shared.observer?.ended(group: pid) }
            if shared.outcome.withLock({ $0.launched }) == nil { shared.launched(nil) }
        }
    }

    /// Splits the child's standard output into messages for the connection.
    private static func read(_ output: SubprocessOutputSequence, into shared: Shared, limit: Int) async throws {
        var splitter = LineSplitter(maximumLineBytes: limit)
        for try await buffer in output {
            for line in splitter.feed(buffer.withUnsafeBytes { Array($0) }) { shared.incoming.yield(line) }
            if splitter.overflowed { throw MessageTooLong(limit: limit) }
        }
    }

    private static func configuration(_ launch: StdioLaunch) -> Configuration {
        let environment = StdioLaunch.childEnvironment(inheriting: launch.inheriting, adding: launch.environment)
        var options = PlatformOptions()
        options.createSession = true
        options.teardownSequence = [
            .gracefulShutDown(toProcessGroup: true, allowedDurationToNextStep: .seconds(1)),
            .send(signal: .kill, toProcessGroup: true, allowedDurationToNextStep: .seconds(1))
        ]
        return Configuration(
            executable: launch.executable.contains("/") ? .path(FilePath(launch.executable)) : .name(launch.executable),
            arguments: Arguments(launch.arguments),
            environment: .custom(
                Dictionary(
                    uniqueKeysWithValues: environment.compactMap { name, value in
                        Environment.Key(rawValue: name).map { ($0, value) }
                    })),
            workingDirectory: launch.workingDirectory.map { FilePath($0) }, platformOptions: options)
    }
}
