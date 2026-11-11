/// How the status line names the folder ask works in (`ui.statusPath`, notes n6 and n63): `"folder"`, its last folder (default);
/// `"home"`, from the home folder; `"full"`; `"off"`.
public enum StatusPathPreference: String, Sendable, CaseIterable {
    case folder, home, full, off
}
