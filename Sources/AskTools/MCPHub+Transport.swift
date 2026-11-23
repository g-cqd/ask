internal import AskAI
public import AskAgentCore
internal import AskMCP
internal import Foundation

extension MCPHub {
    /// What ask names itself to a server. Some servers' front doors refuse a client that names nothing.
    public static let userAgent = "ask/0 (MCP client)"

    /// The real transports: a child process for a server with a `command`, and an HTTPS connection for one with a `url`.
    /// - Parameters:
    ///   - inheriting: the environment a child's minimal one is taken from (ADR-0096): ask's own.
    ///   - jobs: whose watchdog stops each server's process group if ask is killed in a way it cannot see (ADR-0102), or nil for none.
    ///   - sandbox: the run's sandbox, which a server that ``MCPServerSetting/isSandboxed`` runs inside with the network open.
    /// - Returns: the factory a hub is made with.
    public static func standardTransport(
        inheriting: [String: String],
        jobs: JobTable? = nil,
        sandbox: SandboxPolicy = .unrestricted
    ) -> MCPHost.TransportFactory {
        let observer = jobs.map { WatchdogObserver(watchdog: $0.watchdog) }
        let credentials = CredentialFile.standard(environment: inheriting)
        return { server, environment, headers in
            if let command = server.command {
                return StdioTransport(
                    launch(command, server, environment: environment, inheriting: inheriting, sandbox: sandbox),
                    observer: observer
                )
            }
            guard let address = server.url, let url = URL(string: address) else {
                throw MCPError.refusedEndpoint("the setting has no usable address")
            }
            let http = URLSessionTransport()
            // A sign-in kept for it (roadmap 0067), where a token may go: https, or http to this machine. A plain-http server on the
            // network carries none, and keeps working without one.
            let signIn =
                EndpointPolicy.refusal(for: url, carriesCredential: true) == nil
                ? MCPStoredAuthorization(server: MCPOAuthDiscovery.canonical(url), file: credentials, http: http) : nil
            return try HTTPMCPTransport(
                url: url,
                headers: headers.sorted { $0.key < $1.key }.map { (name: $0.key, value: $0.value) },
                userAgent: userAgent,
                http: http,
                authorization: signIn
            )
        }
    }

    /// How `server` is started: `command` itself, or, when it is sandboxed and the run has a sandbox, `command` inside
    /// `sandbox-exec` under the run's policy with the network open (security audit 2026-11-22, MED-10): a server talks to its own
    /// services, but reads and writes only what the model's commands may. `sandbox-exec` looks a bare name up on the server's `PATH`.
    static func launch(
        _ command: String,
        _ server: MCPServerSetting,
        environment: [String: String],
        inheriting: [String: String],
        sandbox: SandboxPolicy
    ) -> StdioLaunch {
        var policy = sandbox
        policy.network = .any
        let sandboxed = server.isSandboxed && !policy.isUnrestricted
        return StdioLaunch(
            executable: sandboxed ? "/usr/bin/sandbox-exec" : command,
            arguments: sandboxed ? SeatbeltProfile(policy).arguments + [command] + server.args : server.args,
            environment: environment,
            workingDirectory: server.cwd,
            inheriting: inheriting
        )
    }
}
