import AskAgentCore

enum DurabilityCase {
    static let all: [(String, SessionFile.Durability)] = [
        ("none", .none), ("barrier (F_BARRIERFSYNC)", .barrier), ("full (F_FULLFSYNC)", .full)
    ]
}
