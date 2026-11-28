internal import Darwin
internal import Foundation
internal import Testing

@testable import AskAgentCore

/// `policy.minimumVersion` and `policy.sessionRetentionDays` (roadmap 0130, ADR-0168): older binaries are refused, invalid SemVer or
/// non-positive retention days are rejected in configuration, and expired unlocked session logs + sidecars are purged while locked
/// open sessions and recent sessions stay untouched.
@Suite("policy.minimumVersion and policy.sessionRetentionDays enforce version floor and transcript retention")
struct PolicySecurityEnforcementTests {
    @Test func `minimumVersion compares SemVer accurately and rejects malformed versions in configuration`() throws {
        var policy = PolicySection()
        policy.minimumVersion = "0.2.0"
        #expect(policy.versionRefusal(runningVersion: "0.1.0-alpha.1")?.contains("policy.minimumVersion") == true)
        #expect(policy.versionRefusal(runningVersion: "0.2.0") == nil)
        #expect(policy.versionRefusal(runningVersion: "0.3.0-alpha.1") == nil)

        #expect(throws: ConfigurationError.self) {
            _ = try ConfigurationFile.parse(
                Array(#"{"policy":{"minimumVersion":"not-a-semver"}}"#.utf8),
                path: "requirements.json",
                isProject: false
            )
        }
        #expect(throws: ConfigurationError.self) {
            _ = try ConfigurationFile.parse(
                Array(#"{"policy":{"sessionRetentionDays":0}}"#.utf8),
                path: "requirements.json",
                isProject: false
            )
        }
    }

    @Test
    func `sessionRetentionDays purges expired unlocked sessions and sidecars while keeping locked and recent ones`()
        throws
    {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("ask-retention-\(UUID().uuidString)", isDirectory: true)
        let proj = root.appendingPathComponent("sessions/proj", isDirectory: true)
        try FileManager.default.createDirectory(at: proj, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let expiredDate = now.addingTimeInterval(-10 * 86_400)
        let recentDate = now.addingTimeInterval(-2 * 86_400)

        func writeSession(_ stem: String, modified: Date) throws -> URL {
            let log = proj.appendingPathComponent("\(stem).jsonl")
            let tasks = proj.appendingPathComponent("\(stem).tasks")
            try Data("{}\n".utf8).write(to: log)
            try Data("{}\n".utf8).write(to: tasks)
            try FileManager.default.setAttributes([.modificationDate: modified], ofItemAtPath: log.path)
            return log
        }

        let oldUnlocked = try writeSession("old-unlocked", modified: expiredDate)
        let oldLocked = try writeSession("old-locked", modified: expiredDate)
        let fresh = try writeSession("fresh", modified: recentDate)

        // Hold an exclusive flock on oldLocked as a live running session does.
        let lockFD = open(oldLocked.path, O_RDONLY | O_CLOEXEC)
        #expect(lockFD >= 0)
        defer { close(lockFD) }
        #expect(flock(lockFD, LOCK_EX | LOCK_NB) == 0)

        let auditURL = root.appendingPathComponent("security-audit.jsonl")
        let audit = SecurityAuditLog(fileURL: auditURL)
        let purged = SessionRetention.purgeExpired(days: 7, stateRoot: root.path, now: now, audit: audit)
        #expect(purged == 1)

        #expect(!FileManager.default.fileExists(atPath: oldUnlocked.path))
        #expect(!FileManager.default.fileExists(atPath: proj.appendingPathComponent("old-unlocked.tasks").path))
        #expect(FileManager.default.fileExists(atPath: oldLocked.path), "locked session must not be deleted")
        #expect(FileManager.default.fileExists(atPath: fresh.path), "recent session must be kept")

        let auditContent = try String(contentsOf: auditURL, encoding: .utf8)
        #expect(auditContent.contains(#""kind":"policy.retention""#) && auditContent.contains(#""sessions":"1""#))
    }
}
