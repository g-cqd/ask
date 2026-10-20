import AskAI
import Foundation
import Testing

@testable import AskAgentCore

/// A tool call's `sandbox` argument (roadmap 0019): it narrows that call, and asking for more than the run allows is
/// refused, naming what was asked. Only the user widens.
@Suite("A call may narrow its own sandbox; asking for more is refused, naming it")
struct SandboxRequestTests {
    // Outside the temporary directory: that is scratch space every sandbox keeps writable and readable.
    private let workspace = "/opt/ask-sandbox-request-test"
    private func request(_ json: String) -> SandboxRequest? {
        try? SandboxRequest.in(JSONObject(validating: Array(json.utf8)))
    }

    @Test func `no sandbox argument is no request, and other arguments are ignored`() throws {
        #expect(try SandboxRequest.in(JSONObject(validating: Array(#"{"command":"ls"}"#.utf8))) == nil)
    }

    @Test func `a malformed request is an error, not ignored`() {
        #expect(throws: SandboxRequestError.self) {
            _ = try SandboxRequest.in(JSONObject(validating: Array(#"{"sandbox":{"network":"lan"}}"#.utf8)))
        }
        #expect(throws: SandboxRequestError.self) {
            _ = try SandboxRequest.in(JSONObject(validating: Array(#"{"sandbox":{"write":"."}}"#.utf8)))
        }
    }

    @Test func `the network narrows, and asking for more than the run allows is refused`() throws {
        let policy = SandboxPolicy(network: .localhost)
        let narrowed = try #require(request(#"{"sandbox":{"network":"none"}}"#))
            .applied(to: policy, workingDirectory: workspace)
        #expect(narrowed == .narrowed(SandboxPolicy(network: SandboxPolicy.Network.none)))
        let wider = try #require(request(#"{"sandbox":{"network":"any"}}"#))
            .applied(to: policy, workingDirectory: workspace)
        #expect(wider == .refused(["network any (this run allows localhost)"]))
    }

    @Test func `write paths resolve against the working directory and must lie inside what the run allows`() throws {
        let anywhere = try #require(request(#"{"sandbox":{"write":[".", "sub"]}}"#))
            .applied(to: SandboxPolicy(), workingDirectory: workspace)
        #expect(anywhere == .narrowed(SandboxPolicy(write: .roots([workspace, workspace + "/sub"]))))
        let confined = SandboxPolicy(write: .roots([workspace + "/sub"]))
        let outside = try #require(request(#"{"sandbox":{"write":["."]}}"#))
            .applied(to: confined, workingDirectory: workspace)
        #expect(outside == .refused(["writing under \(workspace) (this run allows \(workspace)/sub)"]))
        let scratch = try #require(request(#"{"sandbox":{"write":["/private/tmp"]}}"#))
            .applied(to: confined, workingDirectory: workspace)
        #expect(scratch == .narrowed(SandboxPolicy(write: .roots(["/private/tmp"]))), "scratch is always writable")
    }

    @Test func `reads narrow an unrestricted run to an allow-list, and may name the system's directories`() throws {
        let narrowed = try #require(request(#"{"sandbox":{"read":["."]}}"#))
            .applied(to: SandboxPolicy(), workingDirectory: workspace)
        #expect(narrowed == .narrowed(SandboxPolicy(read: .roots([workspace]))))
        let confined = SandboxPolicy(read: .roots([workspace + "/a"]))
        let system = try #require(request(#"{"sandbox":{"read":["/usr/include"]}}"#))
            .applied(to: confined, workingDirectory: workspace)
        #expect(system == .narrowed(SandboxPolicy(read: .roots(["/usr/include"]))))
        let wider = try #require(request(#"{"sandbox":{"read":["/Users"]}}"#))
            .applied(to: confined, workingDirectory: workspace)
        #expect(wider == .refused(["reading under /Users (this run allows \(workspace)/a)"]))
    }

    @Test func `protections survive any narrowing`() throws {
        let protected = SandboxPolicy(denyRead: [SandboxRule(workspace + "/secret", .subpath)])
        guard
            case .narrowed(let policy) = try #require(request(#"{"sandbox":{"network":"none"}}"#))
                .applied(to: protected, workingDirectory: workspace)
        else {
            Issue.record("not narrowed")
            return
        }
        #expect(policy.denyRead == protected.denyRead && policy.denyWrite == protected.denyWrite)
    }

    @Test func `every widening is named at once`() throws {
        let policy = SandboxPolicy(network: SandboxPolicy.Network.none, write: .roots([workspace]))
        let both = try #require(request(#"{"sandbox":{"network":"any","write":["/opt"]}}"#))
            .applied(to: policy, workingDirectory: workspace)
        #expect(
            both
                == .refused(["network any (this run allows none)", "writing under /opt (this run allows \(workspace))"])
        )
    }
}
