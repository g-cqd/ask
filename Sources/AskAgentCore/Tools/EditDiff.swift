internal import AemiDiff

/// An edit's two texts as the lines it removes and adds (roadmap 0152): `- ` before each line of the old text that goes, `+ ` before
/// each line of the new text that replaces it, and two spaces before each line both keep. Lines are cut as git cuts them (a final line
/// break ends a line, a `\r` before it is no part of it) and matched as git's default diff matches them (Myers, with the indent
/// heuristic), which gives what goes before what replaces it.
enum EditDiff {
    static let removed = "- "
    static let added = "+ "
    static let kept = "  "

    static func text(old: String, new: String) -> String {
        let oldLines = DiffModel.lines(of: old)
        let newLines = DiffModel.lines(of: new)
        // The script gives a change's deletions before its insertions, so the rows follow it as it is.
        return LineDiff.diffLines(oldLines, newLines)
            .map { edit in
                switch edit {
                    case .equal(let index, _): kept + oldLines[index]
                    case .delete(let index): removed + oldLines[index]
                    case .insert(let index): added + newLines[index]
                }
            }
            .joined(separator: "\n")
    }
}
