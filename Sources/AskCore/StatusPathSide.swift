/// Which end of the status line the folder sits at (`ui.statusPathSide`, note n6): `"leading"`, right after the mark (default), or
/// `"trailing"`, last.
/// Declared once for the setting and the screen (ADR-0166).
public enum StatusPathSide: String, Sendable, CaseIterable {
    case leading, trailing
}
