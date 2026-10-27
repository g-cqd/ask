import Foundation
import Testing

@testable import AskAI

@Suite("Copilot device approval and token exchange keep credentials separated")
struct CopilotAuthTests {
    @Test func `device login requests only email scope and refuses redirects`() async throws {
        let transport = ScriptedTransport(
            status: 200,
            chunks: [
                #"{"device_code":"device-secret","user_code":"CODE","verification_uri":"https://github.com/login/device","interval":5,"expires_in":900}"#
            ])
        let start = try await CopilotDeviceSignIn(transport: transport).start()
        #expect(start.url.absoluteString == "https://github.com/login/device")
        #expect(!CopilotDeviceSignIn(transport: transport).pollsImmediately)
        let sent = try #require(transport.sent)
        #expect(!sent.allowsRedirects)
        let form = String(decoding: sent.body, as: UTF8.self)
        #expect(form.contains("scope=user%3Aemail"))
        #expect(!form.contains("repo"))
    }

    @Test(arguments: [
        "https://evil.invalid", "http://api.githubcopilot.com", "https://api.githubcopilot.com:443",
        "https://api.githubcopilot.com/path", "https://api.githubcopilot.com?token=x",
        "https://user@api.githubcopilot.com", "https://api.githubcopilot.com.evil.invalid"
    ])
    func `credential endpoints reject every origin escape`(url: String) {
        #expect(throws: SignInError.self) { try CopilotProtocol.endpoint(url) }
    }

    @Test func `local refresh deadline ignores skewed server clock and preserves identity`() async throws {
        let transport = ScriptedTransport(
            status: 200,
            chunks: [
                #"{"token":"short-token","expires_at":1,"refresh_in":600,"endpoints":{"api":"https://api.individual.githubcopilot.com"}}"#
            ])
        let credential = try await CopilotAuthClient(transport: transport)
            .exchange(githubToken: "github-grant", machineID: "machine", deviceID: "device", now: 1_000)
        #expect(credential.expiresAt == 1_600)
        #expect(credential.machineID == "machine" && credential.deviceID == "device")
        let sent = try #require(transport.sent)
        #expect(sent.headers.contains { $0.name == "authorization" && $0.value == "token github-grant" })
        #expect(!sent.allowsRedirects)
    }

    @Test func `polling handles pending and slow down and never prints provider error text`() async throws {
        let startTransport = ScriptedTransport(
            status: 200,
            chunks: [
                #"{"device_code":"secret","user_code":"CODE","verification_uri":"https://github.com/login/device","interval":5,"expires_in":900}"#
            ])
        let device = try await CopilotDeviceSignIn(transport: startTransport).start().session
        let pending = CopilotDeviceSignIn(
            transport: ScriptedTransport(status: 200, chunks: [#"{"error":"authorization_pending"}"#]))
        if case .pending = try await pending.poll(device) {} else { Issue.record("not pending") }
        let slow = CopilotDeviceSignIn(transport: ScriptedTransport(status: 200, chunks: [#"{"error":"slow_down"}"#]))
        if case .slowDown = try await slow.poll(device) {} else { Issue.record("not slow down") }
        let denied = CopilotDeviceSignIn(
            transport: ScriptedTransport(status: 200, chunks: [#"{"error":"secret-echo"}"#]))
        do {
            _ = try await denied.poll(device)
            Issue.record("accepted denied grant")
        } catch { #expect(!String(describing: error).contains("secret-echo")) }
    }
}
