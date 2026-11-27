internal import ArgumentParser
internal import AskAI
internal import AskAgentCore
internal import AskGateway
internal import AskSession
internal import CryptoKit
internal import Foundation

/// `ask gateway`: keys, trust, node runner and gateway server (ADR-0170).
struct GatewayCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "gateway",
        abstract: "Share this computer's sessions with a gateway, or run the gateway itself.",
        discussion:
            "Node side:\n"
            + "  ask gateway fingerprint: this computer's node key and fingerprint.\n"
            + "  ask gateway trust KEY [--label NAME]: trust a controller's public key.\n"
            + "  ask gateway untrust KEY|FINGERPRINT: stop trusting a controller.\n"
            + "  ask gateway list: list trusted controllers.\n"
            + "  ask gateway node: link to gateway.address (pinned to gateway.key) and share sessions.\n\n"
            + "Gateway side:\n"
            + "  ask gateway server-fingerprint: the gateway server's key and fingerprint (for gateway.key).\n"
            + "  ask gateway enroll KEY [--label NAME]: enroll a node's public key on the gateway.\n"
            + "  ask gateway unenroll KEY|FINGERPRINT: remove an enrolled node.\n"
            + "  ask gateway nodes: list enrolled nodes.\n"
            + "  ask gateway serve --nodes-listen IP:PORT [--controllers-port PORT] --access-team TEAM --access-aud AUD\n"
            + "  ask gateway sign-shell [--shell-dir DIR] | --fingerprint: sign the web shell or print the signing key.\n"
            + "  ask gateway launchd --role node|serve [...]: print a launchd user-agent plist."
    )

    // @dl:disable near-clone -- ArgumentParser option declarations: each flag names its long option and help text
    @Argument(
        help:
            "fingerprint, trust, untrust, list, node, server-fingerprint, enroll, unenroll, nodes, serve, sign-shell or launchd."
    )
    var action: String
    @Argument(help: "For trust/untrust/enroll/unenroll: the key, or a fingerprint's first 8+ hex digits.")
    var key: String?
    @Option(help: "For trust or enroll: a human-readable label.") var label = "peer"
    @Option(name: .customLong("nodes-listen"), help: "For serve/launchd: specific LAN IPv4:port for nodes.")
    var nodesListen: String?
    @Option(name: .customLong("nodes-cidr"), help: "For serve/launchd: optional IPv4 CIDR allowed on the nodes door.")
    var nodesCIDR: String?
    @Option(
        name: .customLong("controllers-port"),
        help: "For serve/launchd: loopback port on 127.0.0.1 for cloudflared."
    )
    var controllersPort: Int = 8_787
    @Option(name: .customLong("access-team"), help: "For serve/launchd: Cloudflare Access team name.")
    var accessTeam: String?
    @Option(name: .customLong("access-aud"), help: "For serve/launchd: Cloudflare Access application AUD tag.")
    var accessAud: String?
    @Flag(name: .customLong("insecure-local-no-access"), help: "For local loopback testing without Cloudflare Access.")
    var insecureLocalNoAccess = false
    @Option(name: .customLong("shell-dir"), help: "Directory of the signed web shell.")
    var shellDir: String?
    @Option(help: "For launchd: node or serve.") var role: String?
    @Flag(
        name: .customLong("fingerprint"),
        help: "For sign-shell: print the shell-signing public key and fingerprint only."
    )
    var fingerprintOnly = false
    // @dl:enable near-clone

    func run() async {
        switch action {
            case "fingerprint": printKey(account: GatewayNodeKey.account)
            case "server-fingerprint": printKey(account: GatewayNodeKey.serverAccount)
            case "trust": addEntry(to: .controllers, auditKind: "gateway.trust", verb: "Trusted")
            case "untrust": removeEntry(from: .controllers, auditKind: "gateway.trust", noun: "controller")
            case "list": listEntries(in: .controllers, empty: "No controller is trusted.")
            case "enroll": addEntry(to: .nodes, auditKind: "gateway.enroll", verb: "Enrolled")
            case "unenroll": removeEntry(from: .nodes, auditKind: "gateway.enroll", noun: "node")
            case "nodes": listEntries(in: .nodes, empty: "No node is enrolled.")
            case "node":
                let reason = await GatewayNodeRunner.run { line in
                    FileHandle.standardError.write(Data((line + "\n").utf8))
                }
                fail("ask gateway node: \(reason).", code: 78)
            case "serve": await serve()
            case "sign-shell": signShell()
            case "launchd": printLaunchd()
            default:
                fail(
                    "ask gateway: unknown action \(action). See `ask gateway --help`.",
                    code: 64
                )
        }
    }

    private func printKey(account: String) {
        let loaded: Curve25519.KeyAgreement.PrivateKey
        do { loaded = try GatewayNodeKey.loadOrCreate(account: account, in: try KeychainSecretStore()) } catch {
            fail("ask: \(error)", code: 77)
        }
        print("Key:         \(loaded.publicKey.rawRepresentation.base64EncodedString())")
        print("Fingerprint: \(GatewayKeys.fingerprint(loaded.publicKey))")
    }

    private func addEntry(to role: GatewayTrustFile.Role, auditKind: String, verb: String) {
        guard let key, let parsed = GatewayKeys.publicKey(key) else {
            fail("ask gateway \(action): give a public key, base64 or 64 hex digits.", code: 64)
        }
        var trust = GatewayTrustFile.load(role)
        guard trust.trust(parsed, label: label) else {
            print("Already present: \(GatewayKeys.fingerprint(parsed))")
            return
        }
        GatewayTrustFile.save(trust, role)
        let fp = GatewayKeys.fingerprint(parsed)
        SecurityAuditLog.defaultLog()
            .record(kind: auditKind, outcome: "added", attributes: ["fingerprint": fp])
        Swift.print("\(verb) \(label): \(fp)")
    }

    private func removeEntry(from role: GatewayTrustFile.Role, auditKind: String, noun: String) {
        guard let key else {
            fail("ask gateway \(action): give a key, or a fingerprint's first 8 digits or more.", code: 64)
        }
        var trust = GatewayTrustFile.load(role)
        let removed = trust.untrust(key)
        guard !removed.isEmpty else {
            fail("ask gateway \(action): no single \(noun) matches \(key).", code: 65)
        }
        GatewayTrustFile.save(trust, role)
        for entry in removed {
            let fp = GatewayKeys.publicKey(entry.key).map(GatewayKeys.fingerprint) ?? entry.key
            SecurityAuditLog.defaultLog()
                .record(kind: auditKind, outcome: "removed", attributes: ["fingerprint": fp])
            Swift.print("Removed: \(entry.label) (\(fp))")
        }
    }

    private func listEntries(in role: GatewayTrustFile.Role, empty: String) {
        let trust = GatewayTrustFile.load(role)
        guard !trust.controllers.isEmpty else {
            print(empty)
            return
        }
        for entry in trust.controllers {
            let fp = GatewayKeys.publicKey(entry.key).map(GatewayKeys.fingerprint) ?? "unreadable key"
            Swift.print("\(fp)  \(entry.label)  since \(entry.added)")
        }
    }
}
