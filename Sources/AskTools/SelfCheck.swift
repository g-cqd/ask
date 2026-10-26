internal import Foundation
internal import Subprocess
internal import System

/// Starts a build of ask with `--self-check` and says whether it can start (ADR-0033): the step before a reload
/// replaces the running process with it. Reloading into a binary that cannot start would end the session.
public enum SelfCheck {
    /// What the check found.
    public enum Outcome: Sendable, Equatable {
        /// It started, checked itself and exited 0; what it printed.
        case passed(String)
        /// It did not; why, in a sentence.
        case failed(String)
    }

    /// The time a check gets: a build starts in about 10 ms, and what it checks (configuration, providers) is
    /// small, so ten seconds only ever ends a hang.
    public static let defaultTimeout = Duration.seconds(10)

    /// Runs `executable --self-check`.
    /// - Parameters:
    ///   - executable: the new build.
    ///   - arguments: what follows `--self-check`: the flags the replacement process will be started with, so the
    ///     check loads the configuration it will really run on.
    ///   - environment: the environment the check runs with, or nil for this process's own. ask passes the one it was launched
    ///     with, because its own has had its credentials blanked and a check that finds no key would refuse a build that works (ADR-0113).
    ///   - timeout: how long it gets.
    ///   - clock: what the timeout is measured on.
    /// - Returns: the outcome. Never throws: every way it can go wrong is a ``Outcome/failed(_:)``.
    public static func run(
        _ executable: String, arguments: [String] = [], environment: [String: String]? = nil,
        timeout: Duration = defaultTimeout,
        clock: any Clock<Duration> = ContinuousClock()
    ) async -> Outcome {
        await withTaskGroup(of: Outcome?.self) { group in
            group.addTask { await execute(executable, arguments: arguments, environment: environment) }
            group.addTask {
                // A cancelled sleep is the check finishing first.
                guard (try? await clock.sleep(for: timeout)) != nil else { return nil }
                return .failed("it did not finish within \(timeout.components.seconds) s, so it was stopped")
            }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first ?? .failed("the check was cancelled")
        }
    }

    private static func execute(_ executable: String, arguments: [String], environment: [String: String]?) async
        -> Outcome
    {
        let options = JobProcess.groupOptions(graceSeconds: 1)
        do {
            let result = try await Subprocess.run(
                .path(FilePath(executable)), arguments: .init(["--self-check"] + arguments),
                environment: environment.map(JobProcess.environment) ?? .inherit, platformOptions: options,
                input: .none,
                output: .string(limit: 16 << 10), error: .string(limit: 16 << 10))
            if Task.isCancelled { return .failed("the check was cancelled") }
            let out = result.standardOutput.trimmingCharacters(in: .whitespacesAndNewlines)
            let err = result.standardError.trimmingCharacters(in: .whitespacesAndNewlines)
            switch result.terminationStatus {
                case .exited(0): return .passed(out)
                case .exited(let code): return .failed("it exited \(code)" + (err.isEmpty ? "" : ": " + err))
                case .signaled(let signal): return .failed("it was killed by signal \(signal)")
            }
        } catch {
            return Task.isCancelled ? .failed("the check was cancelled") : .failed("it could not start: \(error)")
        }
    }
}
