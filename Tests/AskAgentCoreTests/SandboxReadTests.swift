import Testing

@testable import AskAgentCore

/// The read allow-list (roadmap 0042): reads outside the chosen roots and the system's own directories are refused,
/// and the profile switches to a deny-default base only when reads are restricted.
@Suite("Restricted reads: the chosen roots and the system, nothing else, and protections still win")
struct SandboxReadTests {
    private let workspace = "/h/work"
    private func restricted(_ roots: [String] = ["/h/work"], denyRead: [SandboxRule] = []) -> SandboxPolicy {
        SandboxPolicy(read: .roots(roots), denyRead: denyRead)
    }

    @Test func `by default reads are unrestricted, as before`() {
        #expect(SandboxPolicy().read == .anywhere)
        #expect(SandboxPolicy().authorize(.read, path: "/h/notes.txt", relativeTo: "/") == .allowed)
    }

    @Test func `a restricted policy reads its roots and the system, and refuses the rest, saying why`() {
        let policy = restricted()
        #expect(policy.authorize(.read, path: "/h/work/a.swift", relativeTo: "/") == .allowed)
        #expect(policy.authorize(.read, path: "/usr/include/stdio.h", relativeTo: "/") == .allowed)
        #expect(policy.authorize(.read, path: "/private/tmp/x", relativeTo: "/") == .allowed)
        guard case .denied(.read, let why) = policy.authorize(.read, path: "/h/notes.txt", relativeTo: "/") else {
            Issue.record("a read outside the roots was allowed")
            return
        }
        #expect(why == "/h/notes.txt is outside the places this run may read.")
    }

    @Test func `a protected path inside a readable root stays unreadable`() {
        let policy = restricted(["/h"], denyRead: [SandboxRule("/h/.aws", .subpath)])
        guard case .denied = policy.authorize(.read, path: "/h/.aws/credentials", relativeTo: "/") else {
            Issue.record("a protected path was readable")
            return
        }
        #expect(policy.authorize(.read, path: "/h/other", relativeTo: "/") == .allowed)
    }

    @Test func `intersecting narrows the readable roots`() {
        let both = restricted(["/h"]).intersecting(restricted(["/h/work", "/elsewhere"]))
        #expect(both.read == .roots(["/h/work"]))
        #expect(SandboxPolicy().intersecting(restricted()).read == .roots([workspace]))
    }

    @Test func `an unrestricted read keeps today's allow-default profile, byte for byte`() {
        #expect(SeatbeltProfile(SandboxPolicy(network: .localhost)).text.hasPrefix("(version 1)\n(allow default)\n"))
    }

    @Test func `a restricted read compiles a deny-default base, its roots as parameters, protections last`() {
        let policy = restricted(["/h/work"], denyRead: [SandboxRule("/h/work/secret", .subpath)])
        let profile = SeatbeltProfile(policy)
        let lines = profile.text.split(separator: "\n").map(String.init)
        #expect(lines.prefix(2) == ["(version 1)", "(deny default)"])
        #expect(profile.text.contains("(sysctl-name \"hw.ncpu\")"), "sysctls are listed, not all allowed")
        #expect(!profile.text.contains("(allow sysctl-read)\n"))
        #expect(profile.parameters.contains { $0.name.hasPrefix("R") && $0.value == "/h/work" })
        #expect(!profile.text.contains("/h/work"), "paths are parameters, never text")
        let allowRead = lines.firstIndex { $0.hasPrefix("(allow file-read* (subpath (param \"R") }
        let denyRead = lines.lastIndex { $0.hasPrefix("(deny file-read*") }
        #expect(allowRead != nil && denyRead != nil && allowRead! < denyRead!)
        #expect(profile.text.contains("(allow network*)"), "network any is an explicit allowance on a deny base")
        #expect(profile.text.contains("(allow file-write*)"), "writes anywhere stays an explicit allowance")
    }

    @Test func `on a deny-default base the network levels are allowances`() {
        let none = SeatbeltProfile(SandboxPolicy(network: .none, read: .roots(["/w"]))).text
        #expect(!none.contains("(allow network*") && !none.contains("(deny network*)"))
        let local = SeatbeltProfile(SandboxPolicy(network: .localhost, read: .roots(["/w"]))).text
        #expect(local.contains("(allow network* (remote ip \"localhost:*\"))") && !local.contains("(allow network*)\n"))
    }
}
