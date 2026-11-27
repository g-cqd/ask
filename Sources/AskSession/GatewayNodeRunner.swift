internal import AemiJSON
internal import AskAI
internal import AskAgentCore
internal import AskGateway
internal import CryptoKit
internal import Darwin
internal import Foundation

/// `ask gateway node` (ADR-0170): this computer's node. It links to the gateway at `gateway.address`, refusing any that does not hold
/// `gateway.key`, publishes the sessions shared here, relays the channels controllers open to them, and links again with a growing
/// pause whenever the link ends, until it is stopped.
package enum GatewayNodeRunner {
    /// Runs the node; returns only when the configuration says it may not run, with the reason.
    package static func run(say: @escaping @Sendable (String) -> Void) async -> String {
        let source = ConfigurationSource.here
        guard let configuration = try? source.layers().result.configuration else {
            return "the configuration cannot be read"
        }
        guard configuration.policy.value.gatewayAllowed != false else {
            return "your organisation does not allow sharing sessions (policy.gatewayAllowed)"
        }
        let gateway = configuration.gateway.value
        guard gateway.enabled == true, let address = gateway.address,
            let (host, port) = GatewaySection.endpoint(address),
            let written = gateway.key, let gatewayKey = GatewayKeys.publicKey(written)
        else { return "set gateway.enabled, gateway.address and gateway.key in your own config file first" }
        let key: Curve25519.KeyAgreement.PrivateKey
        do { key = try GatewayNodeKey.loadOrCreate(in: try KeychainSecretStore()) } catch {
            return "this computer's gateway key cannot be read: \(error)"
        }
        let folder = SessionDirectory.stateRoot(environment: LaunchEnvironment.values) + "/gateway/viewers"
        let audit = SecurityAuditLog.defaultLog(environment: LaunchEnvironment.values)
        var pause = 1
        while !Task.isCancelled {
            say("Linking to the gateway at \(address)…")
            do {
                let link = try await NoiseLink.node(
                    over: try await TCPStream.connect(host: host, port: port),
                    key: key,
                    gatewayKey: gatewayKey
                )
                say(
                    "Linked. Sharing \(SharedSessions.read(folder).count) session(s) with \(GatewayTrustFile.current().controllers.count) trusted controller(s)."
                )
                pause = 1
                await agent(link: link, key: key, folder: folder, audit: audit).run(rescans: rescans())
                await link.close()
                say("The link ended.")
            } catch {
                say("No link: \(error).")
            }
            say("Linking again in \(pause) s.")
            try? await Task.sleep(for: .seconds(pause))
            pause = min(pause * 2, 60)
        }
        return "stopped"
    }

    private static func agent(
        link: NoiseLink,
        key: Curve25519.KeyAgreement.PrivateKey,
        folder: String,
        audit: SecurityAuditLog
    ) -> NodeAgent {
        NodeAgent(
            world: NodeAgent.World(
                send: { try await link.send($0) },
                receive: { try await link.receive() },
                sessions: { SharedSessions.read(folder) },
                trusted: { GatewayTrustFile.current().keys },
                dial: { id in try? UnixSocket.connect(to: folder + "/\(id).sock") },
                audit: { what, controller in
                    audit.record(kind: "gateway.remote", outcome: what, attributes: ["controller": controller])
                }
            ),
            key: key,
            trusts: { GatewayTrustFile.current().trusts($0) }
        )
    }

    /// A reason to look at the shared sessions again, every few seconds, for as long as it is iterated.
    private static func rescans() -> AsyncStream<Void> {
        AsyncStream { continuation in
            let task = Task {
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(3))
                    continuation.yield()
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
