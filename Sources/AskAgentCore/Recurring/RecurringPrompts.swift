/// `/loop` (roadmap 0228, the owner's answers of 2026-11-12): prompts sent again and again on a schedule, in the main conversation.
/// Times are offsets from when the schedule began, so the rules can be checked without waiting. A prompt due while a turn runs is
/// skipped, not stacked. Bounds: at least ``minimumInterval`` apart, at most ``maximumRuns`` runs, gone after ``lifetime``.
public struct RecurringPrompts: Sendable, Equatable {
    public static let minimumInterval: Duration = .seconds(60)
    public static let maximumRuns = 24
    public static let lifetime: Duration = .seconds(7 * 24 * 3600)

    public struct Entry: Sendable, Equatable {
        public let id: Int
        public let every: Duration
        public let prompt: String
        public let created: Duration
        public var next: Duration
        public var runs = 0
        public var skipped = 0
    }

    /// What became of an entry at a tick.
    public enum Tick: Sendable, Equatable {
        /// Send its prompt now.
        case send(id: Int, prompt: String, run: Int)
        /// Due while a turn ran: skipped.
        case skipped(id: Int)
        /// Its last run, or its lifetime, is over: removed.
        case finished(id: Int, runs: Int)
    }

    public private(set) var entries: [Entry] = []
    private var nextID = 1

    public init() {}

    /// Adds `prompt` every `every`, first due one interval after `now`; returns its number.
    public mutating func add(every: Duration, prompt: String, now: Duration) -> Int {
        let id = nextID
        nextID += 1
        entries.append(Entry(id: id, every: every, prompt: prompt, created: now, next: now + every))
        return id
    }

    /// Removes entry `id`; false when there is none.
    public mutating func remove(_ id: Int) -> Bool {
        let before = entries.count
        entries.removeAll { $0.id == id }
        return entries.count < before
    }

    public mutating func removeAll() { entries.removeAll() }

    /// When the next entry is due, nil when there is none.
    public var nextDue: Duration? { entries.map(\.next).min() }

    /// What is due at `now`: each due entry is sent (or skipped while a turn runs), then scheduled one interval later; an entry past
    /// its runs or lifetime is removed.
    public mutating func tick(now: Duration, turnRunning: Bool) -> [Tick] {
        var ticks: [Tick] = []
        for index in entries.indices where entries[index].next <= now {
            if turnRunning {
                entries[index].skipped += 1
                ticks.append(.skipped(id: entries[index].id))
            } else {
                entries[index].runs += 1
                ticks.append(.send(id: entries[index].id, prompt: entries[index].prompt, run: entries[index].runs))
            }
            // Missed intervals are not caught up: the next is one interval from now.
            entries[index].next = now + entries[index].every
        }
        for entry in entries where entry.runs >= Self.maximumRuns || now - entry.created >= Self.lifetime {
            ticks.append(.finished(id: entry.id, runs: entry.runs))
        }
        entries.removeAll { $0.runs >= Self.maximumRuns || now - $0.created >= Self.lifetime }
        return ticks
    }
}
