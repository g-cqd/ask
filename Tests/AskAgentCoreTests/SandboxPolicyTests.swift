import Foundation
import Testing

@testable import AskAgentCore

/// The policy's decisions on real paths: what is refused, what names the refusal, and that no way of combining
/// policies allows what one of them refuses.
@Suite("A policy refuses protected paths however they are reached, and layers never widen")
struct SandboxPolicyTests {
    private let root: String

    init() throws {
        let made = FileManager.default.temporaryDirectory.appending(path: "ask-policy-\(UUID().uuidString)")
        for directory in ["home/.config/ask", "home/.ssh", "home/work", "elsewhere"] {
            try FileManager.default.createDirectory(
                at: made.appending(path: directory), withIntermediateDirectories: true)
        }
        root = String(cString: realpath(made.path, nil))
    }

    private var protectedConfig: SandboxRule { SandboxRule(root + "/home/.config/ask", .subpath) }
    private var protectedKey: SandboxRule { SandboxRule(root + "/home/.ssh/id_ed25519", .literal) }
    private var standard: SandboxPolicy { SandboxPolicy(denyRead: [protectedConfig, protectedKey]) }

    private func decide(_ policy: SandboxPolicy, _ capability: SandboxCapability, _ path: String) -> SandboxDecision {
        policy.authorize(capability, path: path, relativeTo: root + "/home/work")
    }

    @Test func `a refusal names the capability and the path, and says what is protected`() {
        let read = decide(standard, .read, root + "/home/.config/ask/credentials.json")
        guard case .denied(.read, let why) = read else {
            Issue.record("read was \(read)")
            return
        }
        #expect(why.contains(root + "/home/.config/ask/credentials.json"))
        #expect(why.contains(root + "/home/.config/ask and everything under it cannot be read"))
        guard case .denied(.write, let writeWhy) = decide(standard, .write, root + "/home/.config/ask/config.json")
        else {
            Issue.record("write was allowed")
            return
        }
        #expect(writeWhy.contains("cannot be written"))
    }

    @Test func `what is unreadable is unwritable too, and a literal protects only itself`() {
        #expect(!decide(standard, .write, root + "/home/.ssh/id_ed25519").isAllowed)
        #expect(decide(standard, .read, root + "/home/.ssh/id_ed25519.pub").isAllowed)
        #expect(decide(standard, .read, root + "/home/.ssh/config").isAllowed)
        #expect(decide(standard, .write, root + "/home/work/file").isAllowed)
    }

    @Test func `a protected path is refused by symlink, by dangling link, by dot-dot and by spelling`() throws {
        let work = root + "/home/work"
        try FileManager.default.createSymbolicLink(
            atPath: work + "/to-config", withDestinationPath: root + "/home/.config/ask")
        try FileManager.default.createSymbolicLink(
            atPath: work + "/dangling", withDestinationPath: root + "/home/.config/ask/new-file")
        #expect(!decide(standard, .write, "to-config/config.json").isAllowed)
        #expect(!decide(standard, .read, "to-config/credentials.json").isAllowed)
        #expect(!decide(standard, .write, "dangling").isAllowed)
        #expect(!decide(standard, .write, "../.config/ask/x").isAllowed)
        #expect(!decide(standard, .read, "../.config/ASK/credentials.json").isAllowed)
        #expect(!decide(standard, .write, "../.CONFIG/ask/new").isAllowed)
    }

    @Test func `a path that cannot be resolved is refused, not allowed for want of an answer`() throws {
        try FileManager.default.createSymbolicLink(
            atPath: root + "/home/work/loop", withDestinationPath: root + "/home/work/loop")
        for capability in [SandboxCapability.read, .write] {
            guard case .denied(capability, let why) = decide(standard, capability, "loop") else {
                Issue.record("\(capability) of a loop was allowed")
                continue
            }
            #expect(why.contains("cannot be resolved"))
        }
        #expect(!decide(standard, .write, "missing/../x").isAllowed)
    }

    @Test func `a write scope confines writes to its roots`() {
        let confined = SandboxPolicy(write: .roots([root + "/home/work"]))
        #expect(decide(confined, .write, "new.txt").isAllowed)
        guard case .denied(.write, let why) = decide(confined, .write, root + "/elsewhere/x") else {
            Issue.record("a write outside the roots was allowed")
            return
        }
        #expect(why.contains("outside the places this run may write"))
        #expect(decide(confined, .read, root + "/elsewhere/x").isAllowed, "the write scope does not restrict reads")
    }

    @Test func `the intersection of policies refuses whatever either refuses, for every pair and path`() {
        let policies = [
            SandboxPolicy.unrestricted, standard, SandboxPolicy(write: .roots([root + "/home/work"])),
            SandboxPolicy(write: .roots([root + "/elsewhere"]), denyRead: [protectedKey]),
            SandboxPolicy(network: .none, write: .roots([])),
            SandboxPolicy(network: .localhost, denyWrite: [protectedConfig])
        ]
        let paths = [
            root + "/home/work/a", root + "/home/.config/ask/c", root + "/home/.ssh/id_ed25519",
            root + "/home/.ssh/config", root + "/elsewhere/z", root + "/nowhere/q"
        ]
        for left in policies {
            for right in policies {
                let both = left.intersecting(right)
                #expect(both.network == Swift.min(left.network, right.network))
                for capability in [SandboxCapability.read, .write] {
                    for path in paths {
                        let allowed = both.authorize(capability, path: path, relativeTo: root).isAllowed
                        let each =
                            left.authorize(capability, path: path, relativeTo: root).isAllowed
                            && right.authorize(capability, path: path, relativeTo: root).isAllowed
                        #expect(allowed == each, "\(capability) \(path)")
                    }
                }
            }
        }
    }

    @Test func `the network narrows to the lesser of the two, and unrestricted is the identity`() {
        #expect(SandboxPolicy(network: .any).intersecting(SandboxPolicy(network: .localhost)).network == .localhost)
        #expect(SandboxPolicy(network: .none).intersecting(SandboxPolicy(network: .any)).network == .none)
        #expect(standard.intersecting(.unrestricted) == standard)
        #expect(SandboxPolicy.unrestricted.isUnrestricted && !standard.isUnrestricted)
    }
}
