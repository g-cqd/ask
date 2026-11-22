/// How the status line names the folder ask works in (`ui.statusPath`, notes n6 and n63): `"folder"`, its last folder (default);
/// `"home"`, from the home folder; `"full"`; `"off"`.
/// Declared once for the setting and the screen (ADR-0166).
public enum StatusPathForm: String, Sendable, CaseIterable {
    /// Its last folder, the default.
    case folder
    /// From the home folder, `~/src/shop`; in full outside it.
    case home
    /// In full.
    case full
    /// Not shown.
    case off
}
