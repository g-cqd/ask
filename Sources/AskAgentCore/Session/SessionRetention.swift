internal import Darwin
public import Foundation

/// Enforces `policy.sessionRetentionDays` (roadmap 0130, ADR-0168): removes recorded sessions and their sidecars (`.tasks`, `.ideas`,
/// `.db`) across `<stateRoot>/sessions/*/` whose `.jsonl` modification date is older than `days` days, skipping any session file held
/// open by a running `ask` (`LOCK_EX | LOCK_NB`), and records a single count in ``SecurityAuditLog``.
public enum SessionRetention {
    /// Purges sessions older than `days` days under `stateRoot` relative to `now`; returns the number of session logs removed.
    @discardableResult
    public static func purgeExpired(
        days: Int,
        stateRoot: String,
        now: Date = Date(),
        audit: SecurityAuditLog? = nil
    ) -> Int {
        guard days >= 1 else { return 0 }
        let cutoff = now.addingTimeInterval(-Double(days) * 86_400)
        let sessionsRoot = stateRoot + "/sessions"
        let manager = FileManager.default
        guard let projects = try? manager.contentsOfDirectory(atPath: sessionsRoot) else { return 0 }
        var removed = 0
        for project in projects where !project.hasPrefix(".") {
            let projectDir = sessionsRoot + "/" + project
            guard let names = try? manager.contentsOfDirectory(atPath: projectDir) else { continue }
            for name in names where name.hasSuffix(".jsonl") {
                let sessionPath = projectDir + "/" + name
                guard let modified = (try? manager.attributesOfItem(atPath: sessionPath))?[.modificationDate] as? Date,
                    modified < cutoff
                else { continue }
                guard unlinkIfUnlocked(sessionPath) else { continue }
                removed += 1
                let stem = String(sessionPath.dropLast(".jsonl".count))
                for suffix in [".tasks", ".ideas", ".db", ".db-wal", ".db-shm"] {
                    unlink(stem + suffix)
                }
            }
        }
        if removed > 0 {
            audit?
                .record(
                    kind: "policy.retention",
                    outcome: "purged",
                    attributes: ["days": "\(days)", "sessions": "\(removed)"]
                )
        }
        return removed
    }

    /// Acquires an exclusive non-blocking `flock` before unlinking so a running `ask` holding the session lock is never disturbed.
    private static func unlinkIfUnlocked(_ path: String) -> Bool {
        let fd = open(path, O_RDONLY | O_NOFOLLOW | O_CLOEXEC)
        guard fd >= 0 else { return false }
        defer { close(fd) }
        guard flock(fd, LOCK_EX | LOCK_NB) == 0 else { return false }
        defer { _ = flock(fd, LOCK_UN) }
        return unlink(path) == 0
    }
}
