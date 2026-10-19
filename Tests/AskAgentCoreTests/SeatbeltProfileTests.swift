import Testing

@testable import AskAgentCore

/// The compiled profile's text and parameters. What Seatbelt then does with them is tested against the real
/// `sandbox-exec` in SeatbeltEnforcementTests.
@Suite("A policy compiles to a profile whose paths are parameters and whose protections come last")
struct SeatbeltProfileTests {
    private let config = SandboxRule("/h/.config/ask", .subpath)
    private let key = SandboxRule("/h/.ssh/id_rsa", .literal)

    @Test func `an unrestricted policy is the allow-default base and nothing else`() {
        let profile = SeatbeltProfile(.unrestricted)
        #expect(profile.text == "(version 1)\n(allow default)\n")
        #expect(profile.parameters.isEmpty && profile.arguments == ["-p", profile.text])
    }

    @Test func `protected paths are parameters, never text, so a path cannot add a rule`() {
        let hostile = SandboxRule("/h/x\") (allow file-write* (subpath \"/", .subpath)
        let profile = SeatbeltProfile(SandboxPolicy(denyRead: [hostile]))
        #expect(!profile.text.contains("allow file-write*"))
        #expect(!profile.text.contains("/h/x"))
        let named = profile.parameters.filter { $0.value == hostile.path }.map(\.name)
        #expect(named.count == 2 && named.contains { $0.hasPrefix("DW") } && named.contains { $0.hasPrefix("DR") })
        #expect(profile.arguments.contains("\(named[0])=\(hostile.path)"))
    }

    @Test func `denials follow the allowances, so a protected path inside a writable root stays protected`() {
        let policy = SandboxPolicy(write: .roots(["/h/work"]), denyWrite: [config])
        let lines = SeatbeltProfile(policy).text.split(separator: "\n").map(String.init)
        let allow = lines.firstIndex { $0.hasPrefix("(allow file-write*") }
        let deny = lines.lastIndex { $0.hasPrefix("(deny file-write* (subpath") }
        #expect(allow != nil && deny != nil && allow! < deny!)
    }

    @Test func `readable-denied paths are write-denied, and every ancestor's unlink is guarded`() {
        let profile = SeatbeltProfile(SandboxPolicy(denyRead: [key]))
        #expect(profile.text.contains("(deny file-write* (literal (param \"DW0\")))"))
        #expect(profile.text.contains("(deny file-read* (literal (param \"DR1\")))"))
        let guarded = profile.parameters.filter { $0.name.hasPrefix("A") }.map(\.value)
        #expect(guarded == ["/h/.ssh", "/h"])
    }

    @Test func `the network clause follows the policy`() {
        #expect(!SeatbeltProfile(SandboxPolicy(network: .any)).text.contains("network"))
        #expect(SeatbeltProfile(SandboxPolicy(network: .none)).text.contains("(deny network*)"))
        let local = SeatbeltProfile(SandboxPolicy(network: .localhost)).text
        #expect(local.contains("(deny network*)") && local.contains("(allow network* (remote ip \"localhost:*\"))"))
    }

    @Test func `a write scope denies all writes first, then allows its roots and scratch space`() {
        let text = SeatbeltProfile(SandboxPolicy(write: .roots(["/h/work", "/h/more"]))).text
        #expect(
            text.contains("(deny file-write*)\n(allow file-write* (subpath (param \"W0\")) (subpath (param \"W1\"))"))
        #expect(text.contains("(literal \"/dev/null\")") && text.contains("(subpath \"/private/tmp\")"))
    }

    @Test func `ancestors are listed once, whatever number of protected paths share them`() {
        let policy = SandboxPolicy(denyRead: [config, SandboxRule("/h/.config/other", .subpath), key])
        #expect(policy.guardedAncestors == ["/h/.config", "/h", "/h/.ssh"])
    }
}
