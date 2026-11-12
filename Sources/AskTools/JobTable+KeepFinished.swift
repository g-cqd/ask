internal import Synchronization

/// `jobs.keepFinished` (t232; the owner, 2026-11-06): every finished job is kept by default, its unread output with it; with a limit,
/// the oldest finished ones past it are let go, a running one never. Checked when the limit is set, as a job starts and as one ends.
extension JobTable {
    /// The most finished jobs kept; nil for all of them. Setting it lets go at once those past it.
    public var keepFinished: Int? {
        get { retention.withLock { $0.limit } }
        set {
            retention.withLock { $0.limit = newValue.map { Swift.max(0, $0) } }
            letGoFinished()
        }
    }

    /// Whether `name`, an id or a short id with or without `#`, named a job let go.
    func wasLetGo(_ name: String) -> Bool {
        let short = name.hasPrefix("#") ? String(name.dropFirst()) : name
        return retention.withLock { $0.letGo.contains(name) || $0.letGo.contains(short) }
    }

    /// Lets go the oldest finished jobs past the limit.
    func letGoFinished() {
        guard let limit = keepFinished else { return }
        let gone = removeJobs { jobs in
            let finished = jobs.values.filter { $0.status != .running }.sorted { Self.order($0.id) < Self.order($1.id) }
            return Array(finished.prefix(Swift.max(0, finished.count - limit)))
        }
        guard !gone.isEmpty else { return }
        retention.withLock { retention in
            for job in gone {
                retention.letGo.insert(job.id)
                retention.letGo.insert(job.displayID)
            }
        }
    }

    /// A job's place in the order they started.
    static func order(_ id: String) -> Int { Int(id.dropFirst(4)) ?? 0 }
}
