internal import ArgumentParser
internal import AskAI
internal import AskAgentCore
internal import AskGateway
internal import AskSession
internal import CryptoKit
internal import Foundation

/// `ask gateway`: this computer's side of the gateway (ADR-0170). Its key, kept in the keychain, and the controller keys it trusts,
/// kept in `<config>/gateway/trusted.json`. Trusting and untrusting are done here, at the computer, and recorded in the security
/// audit log.
struct GatewayCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "gateway",
        abstract: "This computer's gateway key, and the controller keys it trusts.",
        discussion:
            "ask gateway fingerprint: this computer's key and its fingerprint (made the first time).\n"
            + "ask gateway trust KEY [--label NAME]: trust a controller's public key (base64 or hex).\n"
            + "ask gateway untrust KEY|FINGERPRINT: stop trusting it (a fingerprint's first 8 digits or more).\n"
            + "ask gateway list: the controllers trusted.\n"
            + "ask gateway node: link to the gateway (gateway.address, gateway.key) and share this computer's sessions until stopped."
    )

    @Argument(help: "fingerprint, trust, untrust, list or node.") var action: String
    @Argument(help: "For trust and untrust: the key, or for untrust a fingerprint's start.") var key: String?
    @Option(help: "For trust: what to call the controller, such as the browser it was made in.") var label =
        "controller"

    func run() async {
        switch action {
            case "fingerprint": fingerprint()
            case "trust": trust()
            case "untrust": untrust()
            case "list": list()
            case "node":
                let reason = await GatewayNodeRunner.run { line in
                    FileHandle.standardError.write(Data((line + "\n").utf8))
                }
                fail("ask gateway node: \(reason).", code: 78)
            default: fail("ask gateway: \(action) is not fingerprint, trust, untrust, list or node.", code: 64)
        }
    }

    private func fingerprint() {
        let key: Curve25519.KeyAgreement.PrivateKey
        do { key = try GatewayNodeKey.loadOrCreate(in: try KeychainSecretStore()) } catch {
            fail("ask: \(error)", code: 77)
        }
        print("Key:         \(key.publicKey.rawRepresentation.base64EncodedString())")
        print("Fingerprint: \(GatewayKeys.fingerprint(key.publicKey))")
    }

    private func trust() {
        guard let key, let controller = GatewayKeys.publicKey(key) else {
            fail("ask gateway trust: give a controller's public key, base64 or 64 hex digits.", code: 64)
        }
        var trust = GatewayTrustFile.load()
        guard trust.trust(controller, label: label) else {
            print("Already trusted: \(GatewayKeys.fingerprint(controller))")
            return
        }
        GatewayTrustFile.save(trust)
        let print = GatewayKeys.fingerprint(controller)
        SecurityAuditLog.defaultLog()
            .record(kind: "gateway.trust", outcome: "added", attributes: ["fingerprint": print])
        Swift.print("Trusted \(label): \(print)")
    }

    private func untrust() {
        guard let key else {
            fail("ask gateway untrust: give a key, or a fingerprint's first 8 digits or more.", code: 64)
        }
        var trust = GatewayTrustFile.load()
        let removed = trust.untrust(key)
        guard !removed.isEmpty else {
            fail("ask gateway untrust: no single trusted controller matches \(key).", code: 65)
        }
        GatewayTrustFile.save(trust)
        for controller in removed {
            let print = GatewayKeys.publicKey(controller.key).map(GatewayKeys.fingerprint) ?? controller.key
            SecurityAuditLog.defaultLog()
                .record(kind: "gateway.trust", outcome: "removed", attributes: ["fingerprint": print])
            Swift.print("No longer trusted: \(controller.label) (\(print))")
        }
    }

    private func list() {
        let trust = GatewayTrustFile.load()
        guard !trust.controllers.isEmpty else {
            print("No controller is trusted.")
            return
        }
        for controller in trust.controllers {
            let print = GatewayKeys.publicKey(controller.key).map(GatewayKeys.fingerprint) ?? "unreadable key"
            Swift.print("\(print)  \(controller.label)  since \(controller.added)")
        }
    }
}
