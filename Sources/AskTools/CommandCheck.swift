internal import Foundation

/// A command checked before it runs (roadmap 0188): parsed by the shell that will run it, without running anything, and, for bash or
/// sh, read by shellcheck when it is on the PATH. A command that does not parse is not run; shellcheck's findings are told with the result
/// of a command that failed.
///
/// Parsing runs nothing: `-n` reads without executing, the environment is the PATH alone (no `BASH_ENV`, which bash would source even
/// then), zsh skips its startup files (`-f`) and fish its configuration. shellcheck reads the command from its input and no
/// `.shellcheckrc` (`--norc`). Costs measured on an M3: 2 to 8 ms to parse, about 23 ms for shellcheck. A check that cannot run, or
/// takes more than 3 s, lets the command run as it would have.
enum CommandCheck {
    struct Result: Sendable, Equatable {
        /// What the shell said, when the command does not parse.
        var syntaxError: String?
        /// shellcheck's warnings and errors, one a line, at most ``maximumFindings``.
        var findings: [String] = []
    }

    static let maximumFindings = 5
    static let deadline = Duration.seconds(3)

    static func check(_ command: String, shell: String, path: String?) async -> Result {
        let name = (shell as NSString).lastPathComponent
        let parse = parsing(command, with: name)
        let environment = environment(path: path)
        var result = Result()
        if let parsed = await run(shell, parse, environment: environment), parsed.status != 0 {
            let said = parsed.error.trimmingCharacters(in: .whitespacesAndNewlines)
            result.syntaxError = said.isEmpty ? "\(name) could not parse it" : said
            return result
        }
        guard name == "bash" || name == "sh", let shellcheck = executable("shellcheck", path: path) else {
            return result
        }
        if let checked = await run(shellcheck, linting(name), input: command, environment: environment) {
            result.findings = checked.output.split(separator: "\n").prefix(maximumFindings)
                .map {
                    String($0.hasPrefix("-:") ? $0.dropFirst(2) : $0[...])
                }
        }
        return result
    }

    /// The arguments that make `shell` parse `command` without running it, nor its startup files.
    static func parsing(_ command: String, with shell: String) -> [String] {
        switch shell {
            case "zsh": ["-f", "-n", "-c", command]
            case "fish": ["--no-config", "--no-execute", "-c", command]
            default: ["-n", "-c", command]
        }
    }

    /// shellcheck's arguments for a command of `dialect` on its input: no `.shellcheckrc`, warnings and errors, one finding a line.
    static func linting(_ dialect: String) -> [String] {
        ["--norc", "-s", dialect, "-S", "warning", "-f", "gcc", "-"]
    }

    /// The environment a check runs in: the PATH, and nothing else that a shell could act on (`BASH_ENV`, `ENV`, `ZDOTDIR`).
    static func environment(path: String?) -> [String: String] {
        ["PATH": path ?? "/usr/bin:/bin"]
    }

    /// The first executable called `name` in `path`'s directories.
    static func executable(_ name: String, path: String?) -> String? {
        (path ?? "").split(separator: ":").map { "\($0)/\(name)" }
            .first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    private struct Ran: Sendable {
        let status: Int32
        let output: String
        let error: String
    }

    /// `executable` run to its end with `arguments`, or nil when it could not start or outlived ``deadline``.
    private static func run(
        _ executable: String,
        _ arguments: [String],
        input: String? = nil,
        environment: [String: String]
    ) async -> Ran? {
        await Task.detached {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: executable)
            process.arguments = arguments
            process.environment = environment
            process.currentDirectoryURL = URL(fileURLWithPath: NSTemporaryDirectory())
            let output = Pipe()
            let error = Pipe()
            let feed = Pipe()
            process.standardOutput = output
            process.standardError = error
            process.standardInput = feed
            do { try process.run() } catch { return nil }
            if let input { feed.fileHandleForWriting.write(Data(input.utf8)) }
            try? feed.fileHandleForWriting.close()
            // Stopped past the deadline: a check never holds a command up for long.
            let watchdog = Task {
                try? await Task.sleep(for: deadline)
                if process.isRunning { process.terminate() }
            }
            let out = output.fileHandleForReading.readDataToEndOfFile()
            let err = error.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            watchdog.cancel()
            guard process.terminationReason == .exit else { return nil }
            return Ran(
                status: process.terminationStatus,
                output: String(decoding: out, as: UTF8.self),
                error: String(decoding: err, as: UTF8.self)
            )
        }
        .value
    }
}
