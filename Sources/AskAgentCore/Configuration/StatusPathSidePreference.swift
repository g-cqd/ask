/// Which end of the status line the folder sits at (`ui.statusPathSide`, note n6): `"leading"`, right after the mark (default), or
/// `"trailing"`, last.
public enum StatusPathSidePreference: String, Sendable, CaseIterable {
    case leading, trailing
}
