extension Array where Element: Equatable {
    /// `self` followed by those of `later` it does not already hold, in `later`'s order: how a protective list or a scope takes a
    /// later layer's entries without growing on one it already has (a resumed session's record, say).
    func appendingNew(_ later: [Element]) -> [Element] {
        self + later.filter { !contains($0) }
    }
}
