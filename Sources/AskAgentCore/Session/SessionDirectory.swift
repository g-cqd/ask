public import Foundation

/// Where a project's sessions live: `$XDG_STATE_HOME/ask/sessions/<project>/`, else under
/// `~/.local/state`. Each run creates a new file there, named so a listing sorts by time; creating with
/// `O_EXCL` means two runs never write one file.
public struct SessionDirectory: Sendable, Equatable {
    public let path: String

    /// The directory for the project at `project`, an absolute path.
    public init(
        project: String, environment: [String: String] = ProcessInfo.processInfo.environment,
        home: String = NSHomeDirectory()
    ) {
        path = Self.stateRoot(environment: environment, home: home) + "/sessions/" + Self.projectName(project)
    }

    /// ask's state directory: `$XDG_STATE_HOME/ask`, else `~/.local/state/ask`. Sessions live under it.
    public static func stateRoot(
        environment: [String: String] = ProcessInfo.processInfo.environment, home: String = NSHomeDirectory()
    ) -> String {
        let state = environment["XDG_STATE_HOME"].flatMap { $0.hasPrefix("/") ? $0 : nil } ?? home + "/.local/state"
        return state + "/ask"
    }

    /// Creates the directory if needed, and makes it and the two above it that ask owns (`sessions` and `ask`) the person's alone
    /// (0700, roadmap 0153): the names say which projects were worked on. One made before with the default 0755 is tightened.
    /// - Throws: what the file system says when the directory cannot be made.
    public func create() throws {
        let manager = FileManager.default
        try manager.createDirectory(
            atPath: path, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let sessions = (path as NSString).deletingLastPathComponent
        for owned in [path, sessions, (sessions as NSString).deletingLastPathComponent] {
            try? manager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: owned)
        }
    }

    /// A readable, flat name for a project path: separators become `-`, spaces `_`.
    static func projectName(_ project: String) -> String {
        let parts = project.split(separator: "/").map { $0.replacingOccurrences(of: " ", with: "_") }
        return parts.isEmpty ? "root" : parts.joined(separator: "-")
    }

    /// A path for a new session started at `now`: a UTC timestamp, then random hex so two runs started in the
    /// same second still differ.
    public func newSessionPath(now: Date = Date()) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .gmt
        let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: now)
        let fields = [parts.year, parts.month, parts.day, parts.hour, parts.minute, parts.second].map { $0 ?? 0 }
        let stamp =
            String(fields[0]) + fields[1 ... 2].map { String($0).leftPadded(to: 2) }.joined() + "T"
            + fields[3 ... 5].map { String($0).leftPadded(to: 2) }.joined() + "Z"
        let suffix = (0 ..< 4).map { _ in String(UInt8.random(in: 0 ... 255), radix: 16).leftPadded(to: 2) }.joined()
        return path + "/" + stamp + "-" + suffix + ".jsonl"
    }
}

extension String {
    fileprivate func leftPadded(to width: Int) -> String {
        count >= width ? self : String(repeating: "0", count: width - count) + self
    }
}
