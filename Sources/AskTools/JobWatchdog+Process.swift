internal import Darwin

/// The watchdog's process: a shell, in a session of its own, reading the pipe (ADR-0079).
extension JobWatchdog {
    /// What the shell runs. Each line is `+GROUP` or `-GROUP`, written only by ask. End of input stops the groups still listed.
    /// A group is stopped as ask stops a job: SIGTERM to the group, two seconds, then SIGKILL.
    static let script = """
        trap '' HUP INT
        groups=
        while IFS= read -r line; do
            group=${line#?}
            case $line in
                +*) groups="$groups $group" ;;
                -*)
                    rest=
                    for g in $groups; do [ "$g" = "$group" ] || rest="$rest $g"; done
                    groups=$rest
                    ;;
            esac
        done
        [ -n "$groups" ] || exit 0
        for g in $groups; do kill -TERM -- "-$g" 2>/dev/null; done
        sleep 2
        for g in $groups; do kill -KILL -- "-$g" 2>/dev/null; done
        """

    /// Starts `shell` with `input` as its standard input, in a new session, with nothing else inherited. Closes `input` either way.
    /// - Returns: the shell's process id, or nil if it could not be started.
    static func spawn(shell: String, input: Int32) -> pid_t? {
        defer { close(input) }
        var actions: posix_spawn_file_actions_t?
        var attributes: posix_spawnattr_t?
        guard posix_spawn_file_actions_init(&actions) == 0 else { return nil }
        defer { posix_spawn_file_actions_destroy(&actions) }
        guard posix_spawnattr_init(&attributes) == 0 else { return nil }
        defer { posix_spawnattr_destroy(&attributes) }
        posix_spawn_file_actions_adddup2(&actions, input, 0)
        posix_spawn_file_actions_addopen(&actions, 1, "/dev/null", O_WRONLY, 0)
        posix_spawn_file_actions_addopen(&actions, 2, "/dev/null", O_WRONLY, 0)
        posix_spawnattr_setflags(&attributes, Int16(POSIX_SPAWN_SETSID | POSIX_SPAWN_CLOEXEC_DEFAULT))
        let arguments = ["sh", "-c", script].map { unsafe strdup($0) } + [nil]
        defer { for argument in arguments { unsafe free(argument) } }
        let environment = [unsafe strdup("PATH=/usr/bin:/bin"), nil]
        defer { for entry in environment { unsafe free(entry) } }
        var process: pid_t = 0
        let status = unsafe posix_spawn(&process, shell, &actions, &attributes, arguments, environment)
        return status == 0 ? process : nil
    }
}
