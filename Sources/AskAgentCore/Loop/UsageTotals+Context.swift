extension UsageTotals {
    /// Latest measured context occupancy, e.g. `25%/200k`. Unknown is not presented as zero.
    /// This excludes tool results and messages added since the last measured response.
    public func contextStatus(limit: Int?) -> String {
        guard let limit, limit > 0 else { return "—%/?" }
        let percentage = contextTokens.map { String(Int(Double($0) / Double(limit) * 100)) } ?? "—"
        return "\(percentage)%/\(Self.short(limit))"
    }
}
