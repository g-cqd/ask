extension SandboxPolicy {
    /// What the policy forbids, in words for the model, or nil when it forbids nothing. It goes in the system prompt
    /// and after a command was refused, so the model knows why and does not retry the same thing.
    public var summary: String? {
        guard !isUnrestricted else { return nil }
        var sentences: [String] = []
        let unreadable = denyRead.map(\.path)
        let readonly = denyWrite.filter { !denyRead.contains($0) }.map(\.path)
        if !unreadable.isEmpty {
            sentences.append(
                "These paths cannot be read, written or moved: " + unreadable.joined(separator: ", ") + ".")
        }
        if !readonly.isEmpty {
            sentences.append("These can be read but not written or moved: " + readonly.joined(separator: ", ") + ".")
        }
        if case .roots(let roots) = write {
            let where_ = roots.isEmpty ? "nowhere but" : roots.joined(separator: ", ") + " and"
            sentences.append("Writes are allowed only under \(where_) temporary directories.")
        }
        switch network {
            case .any: break
            case .localhost: sentences.append("The network reaches only this machine.")
            case .none: sentences.append("There is no network access.")
        }
        return "Sandbox: " + sentences.joined(separator: " ")
            + " Only the user can change this; do not try to get around it, and say so if a task needs it."
    }
}
