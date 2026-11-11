internal import Foundation
internal import Subprocess
internal import Synchronization
internal import System

/// Starts the command of an opener the person clicked through (roadmap 0216, ADR-0148): the arguments as they are, with no shell
/// between, no input, and its output discarded. It is the person's own command on the person's own click, so it runs as they would
/// run it, outside the sandbox the model's commands get.
public enum OpenerLaunch {
    /// How the start went.
    public enum Outcome: Sendable, Equatable {
        /// It ran and ended well.
        case finished
        /// It ended with this status, which is not 0.
        case exited(Int32)
        /// It is still running after the wait: left running, as an editor that stays open is.
        case running
        /// It did not start: why.
        case failed(String)
    }

    /// How long a command is waited for before it is left running.
    public static let patience = Duration.seconds(2)

    /// Starts `arguments`, the first of which is the program: a path, or a name looked for on `environment`'s `PATH`.
    ///
    /// The command is waited for `patience`: one that ended says how, and one still running then is left running, since an editor
    /// that stays open is not a failure. Nothing here stops it, whatever becomes of the caller.
    /// - Returns: how it went. Never throws: every way it can go wrong is an ``Outcome/failed(_:)``.
    public static func run(
        _ arguments: [String],
        environment: [String: String],
        workingDirectory: String,
        patience: Duration = patience,
        clock: any Clock<Duration> = ContinuousClock()
    ) async -> Outcome {
        guard let program = arguments.first, !program.isEmpty else { return .failed("no program") }
        guard let executable = executable(program, path: environment["PATH"]) else {
            return .failed(
                program.contains("/") ? "\(program) is not a program that can be run" : "\(program) is not on your PATH"
            )
        }
        let rest = Array(arguments.dropFirst())
        return await withCheckedContinuation { (answer: CheckedContinuation<Outcome, Never>) in
            // Answered once, by whichever comes first: the command's end, or the end of the wait.
            let waiting = Mutex<CheckedContinuation<Outcome, Never>?>(answer)
            let say: @Sendable (Outcome) -> Void = { outcome in
                waiting.withLock { $0.take() }?.resume(returning: outcome)
            }
            let wait = Task.detached {
                guard (try? await clock.sleep(for: patience)) != nil else { return }
                say(.running)
            }
            // Detached and never cancelled: the command is the person's, and goes on when the wait is over.
            Task.detached {
                let outcome = await execute(executable, rest, environment: environment, in: workingDirectory)
                wait.cancel()
                say(outcome)
            }
        }
    }

    private static func execute(
        _ executable: String,
        _ arguments: [String],
        environment: [String: String],
        in directory: String
    ) async -> Outcome {
        var options = PlatformOptions()
        // A session of its own: it is no part of ask's terminal, and outlives ask.
        options.createSession = true
        do {
            let result = try await Subprocess.run(
                .path(FilePath(executable)),
                arguments: Arguments(arguments),
                environment: JobProcess.environment(environment),
                workingDirectory: FilePath(directory),
                platformOptions: options,
                input: .none,
                output: .discarded,
                error: .discarded
            )
            switch result.terminationStatus {
                case .exited(0): return .finished
                case .exited(let code): return .exited(code)
                case .signaled(let signal): return .exited(128 + signal)
            }
        } catch {
            return .failed("it could not start: \(error)")
        }
    }

    /// The file `program` names: itself when it is a path, else the first of its name on `path` that can be run.
    static func executable(_ program: String, path: String?) -> String? {
        func runs(_ candidate: String) -> Bool {
            var isDirectory: ObjCBool = false
            return FileManager.default.fileExists(atPath: candidate, isDirectory: &isDirectory)
                && !isDirectory.boolValue
                && FileManager.default.isExecutableFile(atPath: candidate)
        }
        if program.contains("/") { return runs(program) ? program : nil }
        return (path ?? "/usr/bin:/bin:/usr/sbin:/sbin").split(separator: ":")
            .map { $0 + "/" + program }
            .first(where: runs)
    }
}
