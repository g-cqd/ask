internal import TerminalKitStyle

extension ScreenComposer {
    /// A row brightened under the pointer: no longer dim, and bold, its accents with it.
    static func brightened(_ line: Line) -> Line {
        var line = line
        line.style.dim = false
        line.style.bold = true
        for index in line.accents.indices {
            line.accents[index].style.dim = false
            line.accents[index].style.bold = true
        }
        return line
    }
}
