internal import Foundation

/// The terminal tab's title (notes n49 and n60; the owner's answers of 2026-11-11): `ask · name` once the conversation has a name,
/// `ask · folder` before. Set with OSC 0, the icon name and the window title both, since terminals title their tabs by one or the
/// other; the terminal's own title is saved on its title stack (XTWINOPS 22 and 23) and given back when ask closes.
enum TabTitle {
    /// The longest title, in characters: a tab shows less.
    static let limit = 80

    /// The title for a conversation called `name` in `workspace`: its name, else the folder's, else ask alone; `spinner`'s frame leads
    /// it while a long action runs (note n61). Control characters are
    /// dropped, so nothing in a name can end the sequence or start another.
    static func text(name: String?, workspace: String?, spinner: String? = nil) -> String {
        let named = name.map(clean).flatMap { $0.isEmpty ? nil : $0 }
        let folder = workspace.flatMap { $0.split(separator: "/").last.map(String.init) }.map(clean)
        let lead = spinner.map { $0 + " " } ?? ""
        guard let shown = named ?? folder, !shown.isEmpty else { return lead + "ask" }
        return String((lead + "ask · " + shown).prefix(limit))
    }

    private static func clean(_ text: String) -> String {
        let kept = text.unicodeScalars.filter { $0.properties.generalCategory != .control }
        return String(String.UnicodeScalarView(kept)).trimmingCharacters(in: .whitespaces)
    }

    /// The sequence that sets the title to `text`, ended by ST.
    static func sequence(_ text: String) -> [UInt8] { Array("\u{1B}]0;\(text)\u{1B}\\".utf8) }

    /// Saves the terminal's title, the icon name and the window title, on its stack.
    static let save = Array("\u{1B}[22;0t".utf8)
    /// Gives back the title ``save`` saved.
    static let restore = Array("\u{1B}[23;0t".utf8)
}
