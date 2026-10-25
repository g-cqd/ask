extension SkillReport {
    /// The project skills waiting for trust, and how to give it. Empty when there are none.
    var untrustedLines: [String] {
        guard !catalog.untrusted.isEmpty else { return [] }
        var lines = [
            "project skills not loaded, because they are not trusted as they are now (read each file, then run ask trust --skills in a terminal):"
        ]
        for item in catalog.untrusted {
            let why = item.standing == .changed ? "changed since trusted" : "never trusted"
            lines.append("  \(item.skill.name)  \(item.skill.source)/project  \(why)  \(item.skill.file)")
        }
        return lines
    }
}
