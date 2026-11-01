internal import AskAgentCore
internal import AskTUI
internal import Foundation
internal import Synchronization

extension AgentConversation {
    /// `/encrypt [on|off]` (ADR-0138, roadmap 0182): rewrites this session's file encrypted, or not; before the first prompt, sets how
    /// the session is created. Keys not open yet are opened, or set up, here (idea i1).
    func encrypt(arguments: String, update: @escaping @Sendable (ConversationUpdate) -> Void) async {
        let on: Bool
        switch arguments.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
            case "", "on", "enable", "true", "1": on = true
            case "off", "disable", "false", "0": on = false
            default:
                update(.notice("/encrypt takes on or off.", isError: true))
                return
        }
        let keyring = on ? await keysForEncrypt(update: update) : SessionKeyAccess.keyring
        if on, keyring == nil {
            update(.notice("The keys could not be opened, so nothing was encrypted.", isError: true))
            return
        }
        guard let recorder = session.withLock({ $0 }) else {
            let compressed = SessionKeyAccess.protection.format.compressed
            SessionKeyAccess.settle(
                SessionProtection(
                    format: SessionFormat(compressed: compressed, encrypted: on),
                    keyring: on ? keyring : nil
                ),
                overriding: true
            )
            update(
                .notice(on ? "This session will be encrypted." : "This session will not be encrypted.", isError: false)
            )
            return
        }
        let format = SessionFormat(compressed: recorder.format.compressed, encrypted: on)
        guard format != recorder.format else {
            update(
                .notice(on ? "This session is encrypted already." : "This session is not encrypted.", isError: false)
            )
            return
        }
        do {
            try recorder.change(to: format, keyring: keyring)
            if current.withLock({ $0.settings.configuration.taskScope.value }) == .session {
                try SessionTasks.convert(to: format)
            }
            update(
                .notice(
                    on ? "This session's file is now encrypted." : "This session's file is no longer encrypted.",
                    isError: false
                )
            )
        } catch {
            update(.notice("Cannot change this session's file: \(error)", isError: true))
        }
    }
}
