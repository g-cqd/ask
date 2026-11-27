internal import AemiJSON
internal import AskAI
internal import AskAgentCore
internal import AskGateway
internal import AskSession
internal import AskTools
internal import CryptoKit
internal import Foundation

/// The `serve`, `sign-shell` and `launchd` actions of `ask gateway` (ADR-0170).
extension GatewayCommand {
    private struct ServeOptions {
        let host: String
        let port: UInt16
        let subnet: IPv4Subnet?
        let access: AccessVerifier
    }

    func serve() async {
        let options = validatedServeOptions()
        let serverKey: Curve25519.KeyAgreement.PrivateKey
        do {
            serverKey = try GatewayNodeKey.loadOrCreate(
                account: GatewayNodeKey.serverAccount,
                in: try KeychainSecretStore()
            )
        } catch {
            fail("ask: \(error)", code: 77)
        }
        let defaultShell = ((GatewayTrustFile.path as NSString).deletingLastPathComponent) + "/shell"
        let chosenShell = shellDir ?? (FileManager.default.fileExists(atPath: defaultShell) ? defaultShell : nil)
        let server = GatewayServer()
        let audit = SecurityAuditLog.defaultLog()
        let configuration = GatewayServer.Configuration(
            nodesHost: options.host,
            nodesPort: options.port,
            nodesSubnet: options.subnet,
            controllersPort: UInt16(controllersPort),
            key: serverKey,
            enrolled: { candidate in
                let allowed = GatewayTrustFile.current(.nodes).trusts(candidate)
                let fp = GatewayKeys.fingerprint(candidate)
                audit.record(
                    kind: "gateway.node",
                    outcome: allowed ? "accepted" : "refused",
                    attributes: ["fingerprint": fp]
                )
                return allowed
            },
            access: options.access,
            shell: GatewayShellFiles(directory: chosenShell)
        )
        do {
            let ports = try await server.start(configuration)
            let note =
                "Gateway listening: nodes on \(options.host):\(ports.nodesPort), controllers on 127.0.0.1:\(ports.controllersPort).\n"
            FileHandle.standardError.write(Data(note.utf8))
            while !Task.isCancelled { try? await Task.sleep(for: .seconds(3_600)) }
            await server.stop()
        } catch {
            fail("ask gateway serve: \(error)", code: 78)
        }
    }

    private func validatedServeOptions() -> ServeOptions {
        guard let nodesListen, let (host, port) = GatewaySection.endpoint(nodesListen),
            IPv4Subnet.isSpecificBindAddress(host)
        else {
            fail("ask gateway serve: --nodes-listen takes a specific LAN IPv4:port (never 0.0.0.0).", code: 64)
        }
        guard (1 ... 65_535).contains(controllersPort) else {
            fail("ask gateway serve: --controllers-port must be 1 to 65535.", code: 64)
        }
        var subnet: IPv4Subnet?
        if let nodesCIDR {
            guard let parsed = IPv4Subnet(nodesCIDR) else {
                fail("ask gateway serve: --nodes-cidr takes an IPv4 CIDR such as 192.168.1.0/24.", code: 64)
            }
            subnet = parsed
        }
        if insecureLocalNoAccess {
            return ServeOptions(
                host: host,
                port: UInt16(port),
                subnet: subnet,
                access: AccessVerifier(mode: .insecureLocalNoAccess)
            )
        }
        guard let team = accessTeam, !team.isEmpty, let aud = accessAud, !aud.isEmpty else {
            fail(
                "ask gateway serve: give --access-team and --access-aud (or --insecure-local-no-access for local testing).",
                code: 64
            )
        }
        return ServeOptions(
            host: host,
            port: UInt16(port),
            subnet: subnet,
            access: AccessVerifier.cloudflare(team: team, audience: aud)
        )
    }

    func signShell() {
        let signingKey: Curve25519.Signing.PrivateKey
        do { signingKey = try GatewayNodeKey.loadOrCreateSigningKey(in: try KeychainSecretStore()) } catch {
            fail("ask: \(error)", code: 77)
        }
        let pub = signingKey.publicKey
        let fingerprint = ShellManifest.fingerprint(of: pub)
        if fingerprintOnly {
            print("PublicKey:   \(pub.rawRepresentation.base64EncodedString())")
            print("Fingerprint: \(fingerprint)")
            return
        }
        guard let directory = shellDir else {
            fail("ask gateway sign-shell: give --shell-dir DIR (or --fingerprint).", code: 64)
        }
        do {
            let manifest = try ShellManifest.signDirectory(directory, with: signingKey)
            SecurityAuditLog.defaultLog()
                .record(
                    kind: "gateway.shell",
                    outcome: "signed",
                    attributes: ["files": "\(manifest.files.count)", "fingerprint": fingerprint]
                )
            print("Signed \(manifest.files.count) file(s) in \(directory)")
            print("PublicKey:   \(pub.rawRepresentation.base64EncodedString())")
            print("Fingerprint: \(fingerprint)")
        } catch {
            fail("ask gateway sign-shell: \(error)", code: 65)
        }
    }

    func printLaunchd() {
        guard let executable = BinaryIdentity.running()?.path else {
            fail("ask gateway launchd: cannot locate running ask binary.", code: 70)
        }
        let logs = SessionDirectory.stateRoot(environment: LaunchEnvironment.values) + "/logs"
        switch role {
            case "node":
                print(
                    GatewayLaunchdPlist.render(
                        label: "studio.aemi.ask.gateway.node",
                        arguments: [executable, "gateway", "node"],
                        logDirectory: logs
                    ),
                    terminator: ""
                )
            case "serve":
                guard let nodesListen, let team = accessTeam, let aud = accessAud else {
                    fail(
                        "ask gateway launchd --role serve requires --nodes-listen, --access-team and --access-aud.",
                        code: 64
                    )
                }
                var args = [
                    executable, "gateway", "serve",
                    "--nodes-listen", nodesListen,
                    "--controllers-port", String(controllersPort),
                    "--access-team", team,
                    "--access-aud", aud
                ]
                if let nodesCIDR { args += ["--nodes-cidr", nodesCIDR] }
                if let shellDir { args += ["--shell-dir", shellDir] }
                print(
                    GatewayLaunchdPlist.render(
                        label: "studio.aemi.ask.gateway.server",
                        arguments: args,
                        logDirectory: logs
                    ),
                    terminator: ""
                )
            default:
                fail("ask gateway launchd: give --role node or --role serve.", code: 64)
        }
    }
}
