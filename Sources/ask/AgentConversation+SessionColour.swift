internal import AskAgentCore
internal import AskTUI
internal import Darwin
internal import Foundation
internal import Synchronization

/// A colour of the session's own on the status line (roadmap 0164), so sessions can be told apart: `ui.sessionColor` read every few
/// seconds, so a change to the file applies without a restart.
extension AgentConversation {
    /// How often the setting, and for `others` the other ask processes, are looked at again.
    private static let colourInterval = Duration.seconds(3)

    /// Tells the screen the session's identity while the setting asks for a colour, and nil when it stops; for as long as the screen is open.
    func showSessionColour(update: @escaping @Sendable (ConversationUpdate) -> Void) async {
        var shown: String?
        while !Task.isCancelled {
            let mode = current.withLock { $0.settings.configuration.ui.value.sessionColor } ?? .off
            let wanted: String? =
                switch mode {
                    case .off: nil
                    case .always: sessionSeed()
                    case .others: Self.anotherAskIsRunning() ? sessionSeed() : nil
                }
            if wanted != shown {
                shown = wanted
                update(.sessionIdentity(wanted))
            }
            try? await Task.sleep(for: Self.colourInterval)
        }
    }

    /// The project's path and the session file's name: the same session always gets the same colour.
    func sessionSeed() -> String {
        let path = session.withLock { $0?.path } ?? plannedSessionPath()
        return source.workspace + "|" + (path as NSString).lastPathComponent
    }

    /// The name the next new session will have, chosen once.
    func plannedSessionPath() -> String {
        plannedSession.withLock { planned in
            if let planned { return planned }
            let path = directory.newSessionPath()
            planned = path
            return path
        }
    }

    /// The planned name, used up by the session it names.
    func takePlannedSession() -> String {
        let path = plannedSessionPath()
        plannedSession.withLock { $0 = nil }
        return path
    }

    /// Whether another process of an executable called `ask` runs on this Mac. ask itself is not sandboxed, so it can always look.
    static func anotherAskIsRunning() -> Bool {
        let count = proc_listallpids(nil, 0)
        guard count > 0 else { return false }
        var pids = [pid_t](repeating: 0, count: Int(count) + 32)
        let filled = pids.withUnsafeMutableBytes { proc_listallpids($0.baseAddress, Int32($0.count)) }
        guard filled > 0 else { return false }
        let me = getpid()
        var buffer = [CChar](repeating: 0, count: Int(MAXPATHLEN) * 4)
        for pid in pids.prefix(Int(filled)) where pid > 0 && pid != me {
            let length = proc_pidpath(pid, &buffer, UInt32(buffer.count))
            guard length > 0 else { continue }
            let path = String(decoding: buffer.prefix(Int(length)).map { UInt8(bitPattern: $0) }, as: UTF8.self)
            if (path as NSString).lastPathComponent == "ask" { return true }
        }
        return false
    }
}
