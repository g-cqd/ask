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
        let state = environment["XDG_STATE_HOME"].flatMap { $0.hasPrefix("/") ? $0 : nil } ?? home + "/.local/state"
        path = state + "/ask/sessions/" + Self.projectName(project)
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
