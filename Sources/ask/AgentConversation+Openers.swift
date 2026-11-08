internal import AskAgentCore
internal import AskTUI
internal import Foundation
internal import Synchronization

/// What a clicked link opens with (roadmap 0216, ADR-0148): the person's openers, read from their own configuration only.
extension AgentConversation {
    func opening(for uri: String) -> LinkOpening {
        let openers = current.withLock { $0.settings.configuration.openers.value }
        guard openers != OpenersSection(),
            let link = ClickedLink(
                uri: uri,
                isDirectory: { path in
                    var isDirectory: ObjCBool = false
                    return FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory)
                        && isDirectory.boolValue
                }
            )
        else { return .system }
        switch OpenerChoice.choose(for: link, in: openers) {
            case .system: return .system
            case .app(let name): return .app(name)
            case .command(let arguments, let rule): return .command(arguments, rule: rule)
            case .refused(let reason): return .refused(reason)
        }
    }
}
