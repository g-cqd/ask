/// `ui.dim` (note n13): how faint secondary text is drawn. `normal` (the default) is ask's own grey, `faint` and `fainter` are nearer
/// the page. Declared once for the setting and the screen (ADR-0166); the screen's grey for each is in AskTUI (`Dim+Screen`).
public enum Dim: String, Sendable, CaseIterable {
    case normal, faint, fainter
}
