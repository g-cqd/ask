/// The words the person's messages may hold as a token (roadmaps 0185, 0186): their messages are laid out again when the set changes.
extension Transcript {
    /// `names` with their sigil: `/skill:debugging`, `#t3`.
    public mutating func setTokenNames(_ names: Set<String>) {
        guard names != tokenNames else { return }
        tokenNames = names
        for index in items.indices {
            if case .user = items[index] { revisions[index] = bump() }
        }
    }
}
