internal import Foundation

/// Request-driven refresh under the cross-process lock. Sign-out or replacement during refresh wins the CAS.
public struct CopilotAccess: Sendable {
    public let file: CredentialFile
    let client: CopilotAuthClient
    public init(file: CredentialFile, transport: any HTTPTransport) {
        self.file = file
        client = CopilotAuthClient(transport: transport)
    }

    public func credentials(now: Double) async throws -> CopilotCredentials {
        let stored = try load()
        if stored.expiresAt > now + 30 { return stored }
        let lock = try await CredentialLock.acquire(beside: file.url, wait: .seconds(30))
        defer { lock.release() }
        let current = try load()
        if current.expiresAt > now + 30 { return current }
        let fresh = try await client.exchange(
            githubToken: current.githubToken, machineID: current.machineID, deviceID: current.deviceID, now: now)
        guard try file.saveCopilot(fresh, ifStill: current) else {
            guard let latest = try file.loadCopilot(), latest.expiresAt > now + 30 else {
                throw SignInError.invalidResponse("Copilot account changed during refresh")
            }
            return try latest.validated()
        }
        return fresh
    }

    private func load() throws -> CopilotCredentials {
        guard let stored = try file.loadCopilot() else {
            throw SignInError.invalidResponse("Sign in with ask login copilot-vscode")
        }
        return try stored.validated()
    }
}
