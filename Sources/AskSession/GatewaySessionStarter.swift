internal import AskCore
internal import AskGateway
internal import Darwin
internal import Foundation

/// Starts a new interactive `ask` session in a pseudo-terminal of its own so a gateway viewer can attach to it (ADR-0170), and keeps
/// draining its local pseudo-terminal until the session exits.
enum GatewaySessionStarter {
    /// Spawns `executable` in `folder` at `size`, waits up to `timeout` for `<viewersFolder>/<pid>.sock` to appear, and returns the
    /// session id (`String(pid)`).
    static func start(
        executable: String,
        in folder: String,
        size: ChannelMessage.Size,
        viewersFolder: String,
        environment: [String: String],
        timeout: Duration = .seconds(10)
    ) async -> Result<String, GatewayStartPolicy.Refusal> {
        guard let terminal = try? PseudoTerminal(columns: size.columns, rows: size.rows) else {
            return .failure(.init(reason: "no pseudo-terminal could be made"))
        }
        let spawned = spawn(executable: executable, in: folder, replica: terminal.replica, environment: environment)
        Darwin.close(terminal.replica)
        guard case .success(let pid) = spawned else {
            Darwin.close(terminal.primary)
            if case .failure(let refusal) = spawned { return .failure(refusal) }
            return .failure(.init(reason: "ask could not be started"))
        }
        // Drain the host pseudo-terminal so the child's writes never block; reap the child when it closes.
        let primary = terminal.primary
        Task.detached {
            for await _ in DescriptorReader.pieces(of: primary, finished: { Darwin.close(primary) }) {}
            var status: Int32 = 0
            while waitpid(pid, &status, 0) < 0 && errno == EINTR {}
        }
        let id = String(pid)
        let socketPath = viewersFolder + "/\(id).sock"
        let clock = ContinuousClock()
        let deadline = clock.now + timeout
        while clock.now < deadline {
            if FileManager.default.fileExists(atPath: socketPath) { return .success(id) }
            guard kill(pid, 0) == 0 else {
                return .failure(.init(reason: "the new session exited before opening its screen"))
            }
            try? await Task.sleep(for: .milliseconds(40))
        }
        kill(pid, SIGTERM)
        return .failure(.init(reason: "the new session did not open its screen in time"))
    }

    private static func spawn(
        executable: String,
        in folder: String,
        replica: Int32,
        environment: [String: String]
    ) -> Result<pid_t, GatewayStartPolicy.Refusal> {
        var actions: posix_spawn_file_actions_t?
        guard posix_spawn_file_actions_init(&actions) == 0 else {
            return .failure(.init(reason: "spawn actions failed"))
        }
        defer { posix_spawn_file_actions_destroy(&actions) }
        for target: Int32 in [STDIN_FILENO, STDOUT_FILENO, STDERR_FILENO] {
            _ = posix_spawn_file_actions_adddup2(&actions, replica, target)
        }
        if replica > STDERR_FILENO { _ = posix_spawn_file_actions_addclose(&actions, replica) }
        _ = folder.withCString { unsafe posix_spawn_file_actions_addchdir(&actions, $0) }

        var attributes: posix_spawnattr_t?
        guard posix_spawnattr_init(&attributes) == 0 else {
            return .failure(.init(reason: "spawn attributes failed"))
        }
        defer { posix_spawnattr_destroy(&attributes) }
        _ = posix_spawnattr_setflags(&attributes, Int16(POSIX_SPAWN_SETSID))

        var env = environment
        if env["TERM"] == nil { env["TERM"] = "xterm-256color" }
        let argv = [strdup(executable), nil]
        defer { for pointer in argv where pointer != nil { unsafe free(pointer) } }
        let envp = env.map { strdup("\($0.key)=\($0.value)") } + [nil]
        defer { for pointer in envp where pointer != nil { unsafe free(pointer) } }

        var pid: pid_t = 0
        let code = executable.withCString { path in
            var args = argv
            var vars = envp
            return unsafe posix_spawn(&pid, path, &actions, &attributes, &args, &vars)
        }
        guard code == 0 else { return .failure(.init(reason: "posix_spawn failed (\(code))")) }
        return .success(pid)
    }
}
