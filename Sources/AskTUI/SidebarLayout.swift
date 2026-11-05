/// Where the open sidebar goes (`ui.sidebarLayout`, notes n39, n40).
public enum SidebarLayout: String, Sendable, Equatable, CaseIterable {
    /// Beside the transcript, its whole height.
    case full
    /// In the bottom band, beside the input; the transcript keeps the whole width.
    case bottom
    /// The band where the full sidebar would leave the transcript under 100 columns, the full sidebar elsewhere.
    case adaptive
}
