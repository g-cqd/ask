/// Which end of the status line the folder sits at (`ui.statusPathSide`, note n6): right after the mark, or last.
public enum StatusPathSide: String, Sendable, CaseIterable {
    case leading, trailing
}
