/// The workspace's git state for the status bar (roadmap 0186; the owner, 2026-11-12: at the end of the status bar). One
/// `git status --porcelain=v2 --branch` answers it all, about 10 ms; it is read off the screen's thread, at the start, after a tool
/// call and when a run ends, never on the input path, through ``GitQuery``: nothing the repository's configuration names runs, and
/// submodules are not entered (each has a configuration of its own).
public enum GitStatus {
    /// The forms the status bar fits, longest first: `main ↑2 ↓1 · 3 changed`, `main ↑2↓1 ·3`, `main`; empty outside a repository.
    public static func read(in directory: String, path: String?) async -> [String] {
        let status = ["status", "--porcelain=v2", "--branch", "--ignore-submodules=all"]
        return await GitQuery.output(status, in: directory, path: path).map(forms) ?? []
    }

    static func forms(porcelain: String) -> [String] {
        var branch = ""
        var commit = ""
        var ahead = 0
        var behind = 0
        var changed = 0
        for line in porcelain.split(separator: "\n") {
            let fields = line.split(separator: " ")
            switch (fields.first, fields.dropFirst().first) {
                case ("#", "branch.head"): branch = fields.dropFirst(2).joined(separator: " ")
                case ("#", "branch.oid"): commit = String(fields.dropFirst(2).first?.prefix(7) ?? "")
                case ("#", "branch.ab"):
                    ahead = Int(fields.dropFirst(2).first?.dropFirst() ?? "") ?? 0
                    behind = Int(fields.dropFirst(3).first?.dropFirst() ?? "") ?? 0
                case ("1", _), ("2", _), ("u", _), ("?", _): changed += 1
                default: break
            }
        }
        if branch == "(detached)" { branch = commit }
        guard !branch.isEmpty else { return [] }
        let arrows = [ahead > 0 ? "↑\(ahead)" : nil, behind > 0 ? "↓\(behind)" : nil].compactMap(\.self)
        let full = ([branch] + arrows).joined(separator: " ") + (changed > 0 ? " · \(changed) changed" : "")
        let short =
            ([branch] + (arrows.isEmpty ? [] : [arrows.joined()])).joined(separator: " ")
            + (changed > 0 ? " ·\(changed)" : "")
        var forms: [String] = []
        for form in [full, short, branch] where !forms.contains(form) { forms.append(form) }
        return forms
    }
}
