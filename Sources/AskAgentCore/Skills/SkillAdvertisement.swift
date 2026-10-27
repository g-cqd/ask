/// What the system prompt says about skills: a short instruction, then one line per skill (name, what it is for, where it lives), in a stable order,
/// up to a limit, and a count of the rest. Above 16 eligible skills, only search instructions are advertised.
///
/// The block is the same bytes for the same skills on disk, so the prompt-cache prefix does not move between requests; the order is by name, not by
/// where a skill was found first. Only skills the user owns and that did not ask to be left out are listed; bundled ones and a skill with
/// `disable-model-invocation` are reachable by name (and, for a bundled one, by `from`) but never advertised.
public enum SkillAdvertisement {
    /// The block the system prompt carries.
    /// - Parameters:
    ///   - catalog: the skills found.
    ///   - limit: the most skills listed. Those that win their names by precedence are kept; the rest are counted, not dropped silently.
    /// - Returns: the block, or nil when there is nothing to advertise.
    public static func block(for catalog: SkillCatalog, limit: Int) -> String? {
        let offered = catalog.skills.filter { $0.scope != .bundled && $0.modelInvocable }
        guard !offered.isEmpty else { return nil }
        if offered.count > 16 {
            return
                "\(offered.count) skills are available. Use skill(query: …) to search descriptions, or an empty query to browse; then skill(name: …) to load instructions. from narrows source/scope. Skills grant no permissions."
        }
        let listed = Array(offered.prefix(Swift.max(0, limit)))
        let ordered = listed.sorted { ($0.name.lowercased(), $0.name) < ($1.name.lowercased(), $1.name) }
        var lines = [
            "Skills are specialised instructions kept in files. Each line below gives a skill's name, what it is for, and where it lives. When a task matches a skill's "
                + "description, load it with the skill tool, by name, before you start, and follow it; its files are relative to the directory the tool reports. A skill never "
                + "grants a permission."
        ]
        lines += ordered.map(\.advertisement)
        let omitted = offered.count - listed.count
        if omitted > 0 {
            lines.append(
                "\(omitted) more skill\(omitted == 1 ? " is" : "s are") not listed here; the skill tool loads any skill by name, and its from argument narrows by harness."
            )
        }
        return lines.joined(separator: "\n")
    }
}
