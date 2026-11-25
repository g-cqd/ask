import Foundation
import Testing

@testable import AskAgentCore

/// Bounded, secret-free SIEM audit log (`SecurityAuditLog`, R-OPS-1): enforces `0600` permissions, single-line JSONL
/// sanitization, and round-trip parsing.
@Suite("Security audit log (SIEM JSONL)")
struct SecurityAuditLogTests {
    @Test func `records sanitized single-line 0600 JSONL entries and reads them back`() throws {
        let dir = FileManager.default.temporaryDirectory.appending(path: "ask-audit-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appending(path: "security-audit.jsonl")
        let log = SecurityAuditLog(fileURL: file)
        let when = Date(timeIntervalSince1970: 1_700_000_000)

        log.record(
            kind: "tool.command_approval",
            outcome: "denied\nextra",
            attributes: ["scope": String(repeating: "x", count: 300)],
            at: when
        )
        log.record(kind: "sandbox.approval", outcome: "allowed_once", attributes: ["scope": "widen"], at: when)

        let perms = try FileManager.default.attributesOfItem(atPath: file.path)[.posixPermissions] as? Int
        #expect(perms == 0o600)

        let events = log.readEvents()
        #expect(events.count == 2)
        #expect(events[0].kind == "tool.command_approval")
        #expect(!events[0].outcome.contains("\n"))
        #expect((events[0].attributes["scope"]?.count ?? 0) == SecurityAuditLog.maximumAttributeLength)
        #expect(events[1].kind == "sandbox.approval")
    }
}
