internal import AskAgentCore
internal import AskTUI
internal import Foundation
internal import Synchronization

extension AgentConversation {
    /// `/encrypt [on|off]` (ADR-0138, roadmap 0182): rewrites this session's file encrypted, or not; before the first prompt, sets how
    /// the session is created. The keys are opened before the screen, so a run that has none says how to get them.
    func encrypt(arguments: String, update: @Sendable (ConversationUpdate) -> Void) {
        let on: Bool
        switch arguments.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
            case "", "on", "enable", "true", "1": on = true
            case "off", "disable", "false", "0": on = false
            default:
                update(.notice("/encrypt takes on or off.", isError: true))
                return
        }
        let keyring = SessionKeyAccess.keyring
        if on, keyring == nil {
            update(
                .notice(
                    "The keys are not open in this run. Set sessionEncryption to \"on\" and start ask again: it sets them up or asks the "
                        + "password before the screen opens.",
                    isError: true
                )
            )
            return
        }
        guard let recorder = session.withLock({ $0 }) else {
            let compressed = SessionKeyAccess.protection.format.compressed
            SessionKeyAccess.decide(
                SessionProtection(
                    format: SessionFormat(compressed: compressed, encrypted: on),
                    keyring: on ? keyring : nil
                )
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
