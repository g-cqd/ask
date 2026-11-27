internal import AskAgentCore
internal import Darwin
internal import Foundation

extension ViewerEndpoint {
    /// The endpoint this process's screen is viewed through, when this computer shares its sessions (`gateway.enabled`) and the
    /// organisation does not forbid it (`policy.gatewayAllowed`); nil otherwise, or when its socket cannot be made, which `notice`
    /// is told.
    static func start(
        _ settings: RunSettings,
        workspace: String,
        environment: [String: String],
        notice: (String) -> Void
    ) -> ViewerEndpoint? {
        let configuration = settings.configuration
        guard configuration.gateway.value.enabled == true else { return nil }
        guard configuration.policy.value.gatewayAllowed != false else {
            notice(
                "gateway.enabled is on, but your organisation does not allow sharing sessions (policy.gatewayAllowed)."
            )
            return nil
        }
        let root = SessionDirectory.stateRoot(environment: environment)
        let audit = SecurityAuditLog.defaultLog(environment: environment)
        do {
            return try ViewerEndpoint(
                in: root + "/gateway/viewers",
                description: Description(
                    id: String(getpid()),
                    folder: workspace,
                    label: settings.label,
                    started: ISO8601DateFormatter().string(from: Date())
                ),
                audit: { what, detail in
                    audit.record(
                        kind: "gateway.viewer",
                        outcome: what,
                        attributes: detail.isEmpty ? [:] : ["size": detail]
                    )
                }
            )
        } catch {
            notice("This session cannot be shared with the gateway: \(error).")
            return nil
        }
    }
}
