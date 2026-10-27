/// Some Responses servers rotate item IDs but retain output_index; others omit indexes entirely.
/// Keep both names for the same item, scoped to one response, without ever deduplicating its text.
struct ResponsesItemIdentity {
    private var indexes: [Int: String] = [:]
    private var aliases: [String: String] = [:]

    mutating func resolve(_ rawID: String?, index: Int?) -> String? {
        guard let index, index >= 0 else { return rawID.map { aliases[$0] ?? $0 } }
        let id = indexes[index] ?? rawID.map { aliases[$0] ?? $0 } ?? "output-\(index)"
        indexes[index] = id
        if let rawID { aliases[rawID] = id }
        return id
    }
}
