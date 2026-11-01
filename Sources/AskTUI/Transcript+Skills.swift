/// The skills the person's messages may name as a token (roadmap 0185): their messages are laid out again when the list changes.
extension Transcript {
    /// `names` are command names, `skill:debugging`.
    public mutating func setSkillNames(_ names: Set<String>) {
        guard names != skillNames else { return }
        skillNames = names
        for index in items.indices {
            if case .user = items[index] { revisions[index] = bump() }
        }
    }
}
