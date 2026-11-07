/// `ui.dim` (note n13): how faint secondary text is drawn. `normal` (the default) is ask's own grey, `faint` and `fainter` are nearer
/// the page.
public enum DimPreference: String, Sendable, CaseIterable {
    case normal, faint, fainter
}
