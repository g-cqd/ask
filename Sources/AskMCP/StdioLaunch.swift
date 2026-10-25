/// How to start a stdio server.
public struct StdioLaunch: Sendable, Equatable {
    /// The program: a path, or a name looked up on the child's `PATH`.
    public var executable: String
    /// Its arguments.
    public var arguments: [String]
    /// Variables the configuration names, set on top of the minimal environment. The only way a secret reaches the server.
    public var environment: [String: String]
    /// Where it runs, or nil for where ask runs.
    public var workingDirectory: String?
    /// The environment the minimal one is taken from: ask's own, unless a test says otherwise.
    public var inheriting: [String: String]

    /// A launch. Pass `ProcessInfo.processInfo.environment` as `inheriting` to run as ask does.
    public init(
        executable: String, arguments: [String], environment: [String: String] = [:], workingDirectory: String? = nil,
        inheriting: [String: String]
    ) {
        self.executable = executable
        self.arguments = arguments
        self.environment = environment
        self.workingDirectory = workingDirectory
        self.inheriting = inheriting
    }

    /// What the server's process gets: what a program needs to run (`PATH`, `HOME`, `USER`, `LOGNAME`, `SHELL`, `TERM`, `TMPDIR`, the locale),
    /// then `adding`. Not ask's other variables: its environment holds API keys and the user's tokens, and a server is third-party code.
    /// - Parameters:
    ///   - inheriting: the environment to take the minimal one from.
    ///   - adding: what the configuration names; wins over the inherited.
    /// - Returns: the child's whole environment.
    static func childEnvironment(inheriting: [String: String], adding: [String: String]) -> [String: String] {
        var environment = inheriting.filter { name, _ in
            Self.passed.contains(name) || name.hasPrefix("LC_")
        }
        for (name, value) in adding { environment[name] = value }
        return environment
    }

    private static let passed: Set<String> = [
        "PATH", "HOME", "USER", "LOGNAME", "SHELL", "TERM", "TMPDIR", "LANG", "LANGUAGE"
    ]
}
