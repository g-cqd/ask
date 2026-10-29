extension RequestContext {
    /// What a list of repairs did, said for a person: one clause per kind, with its count.
    public static func describe(_ repairs: [Repair]) -> String {
        var interrupted = 0
        var orphaned = 0
        var dropped: [String] = []
        for repair in repairs {
            switch repair {
                case .interruptedToolCall: interrupted += 1
                case .orphanedToolResult: orphaned += 1
                case .droppedBlock(let type): dropped.append(type)
            }
        }
        var clauses: [String] = []
        if interrupted > 0 {
            clauses.append(
                interrupted == 1
                    ? "a tool call with no result was answered as interrupted"
                    : "\(interrupted) tool calls with no result were answered as interrupted")
        }
        if orphaned > 0 {
            clauses.append(
                orphaned == 1
                    ? "a tool result whose call is gone was left out"
                    : "\(orphaned) tool results whose calls are gone were left out")
        }
        if !dropped.isEmpty {
            let kinds = Array(Set(dropped)).sorted().joined(separator: ", ")
            clauses.append(
                dropped.count == 1
                    ? "a block ask cannot send back (\(kinds)) was left out"
                    : "\(dropped.count) blocks ask cannot send back (\(kinds)) were left out")
        }
        return clauses.joined(separator: "; ")
    }
}
