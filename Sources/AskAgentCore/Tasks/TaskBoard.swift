internal import Foundation
internal import Synchronization

/// The task list of the session in use (ADR-0140), for the `tasks` tool and `/tasks`: attached when a session is made, resumed or forked,
/// read and changed through its file, so a list a workspace's sessions share stays one list.
public final class TaskBoard: Sendable {
    private let log = Mutex<TaskLog?>(nil)

    public init() {}

    /// The list file for the session at `sessionPath`: `<session>.tasks` beside it, or `tasks.ask` beside the workspace's sessions.
    public static func path(forSessionAt sessionPath: String, scope: TaskScope) -> String {
        switch scope {
            case .session: (sessionPath.hasSuffix(".jsonl") ? String(sessionPath.dropLast(6)) : sessionPath) + ".tasks"
            case .workspace: (sessionPath as NSString).deletingLastPathComponent + "/tasks.ask"
        }
    }

    /// Uses the list of the session at `sessionPath`, kept as that session is.
    public func attach(sessionPath: String, format: SessionFormat, keyring: SessionKeyring?, scope: TaskScope) throws {
        let opened = try TaskLog(
            path: Self.path(forSessionAt: sessionPath, scope: scope),
            format: format,
            keyring: keyring
        )
        log.withLock { $0 = opened }
    }

    public func detach() { log.withLock { $0 = nil } }

    public var isAttached: Bool { log.withLock { $0 != nil } }

    /// The list as its file now holds it; nil before a session is attached.
    public func current() throws -> TaskList? {
        guard let attached = log.withLock({ $0 }) else { return nil }
        return try attached.current()
    }

    /// Makes the change `make` returns for the current list; nil before a session is attached.
    @discardableResult
    public func change(_ make: (TaskList) -> TaskChange) throws -> TaskList? {
        guard let attached = log.withLock({ $0 }) else { return nil }
        return try attached.change(make)
    }

    /// The list kept in `format` from now on, written again in it, as its session is by `/encrypt`.
    public func convert(to format: SessionFormat) throws {
        guard let attached = log.withLock({ $0 }) else { return }
        try attached.convert(to: format)
    }

    /// The list of the session at `original` copied for its fork at `fork`, when the list is the session's own.
    public static func copyForFork(from original: String, to fork: String, scope: TaskScope) {
        guard scope == .session else { return }
        let source = path(forSessionAt: original, scope: .session)
        guard FileManager.default.fileExists(atPath: source) else { return }
        try? FileManager.default.copyItem(atPath: source, toPath: path(forSessionAt: fork, scope: .session))
    }
}
