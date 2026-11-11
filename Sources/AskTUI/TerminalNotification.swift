internal import Foundation
internal import TerminalKitInput

/// How a notification (`ui.notify`, note n62) reaches the person through the terminal they run ask in: a bell, or the desktop
/// notification the terminal reads. ask launches nothing to notify; the terminal shows it. OSC 9 for iTerm2, Ghostty and WezTerm;
/// kitty's own OSC 99; OSC 777 for the rest; Terminal.app has no such sequence, so it gets the bell, which it marks the tab and the
/// Dock with.
struct TerminalNotification: Sendable {
    private enum Way { case none, bell, osc9, kitty, osc777 }

    private let way: Way

    init(style: NotifyStyle, environment: [String: String]) {
        switch style {
            case .off: way = .none
            case .bell: way = .bell
            case .notification: way = Self.way(for: environment)
        }
    }

    private static func way(for environment: [String: String]) -> Way {
        if environment["TMUX"] == nil, environment["TERM_PROGRAM"] == "iTerm.app" { return .osc9 }
        switch TerminalIdentity(environment: environment) {
            case .ghostty, .wezterm: return .osc9
            case .kitty: return .kitty
            case .appleTerminal: return .bell
            case .unknown: return .osc777
        }
    }

    /// What tells the terminal to notify with `text`; nothing when notifications are off. Control characters are dropped, so the
    /// text cannot end the sequence, and OSC 777's separator is a comma in it.
    func sequence(_ text: String) -> [UInt8] {
        let kept = String(
            String.UnicodeScalarView(text.unicodeScalars.filter { $0.properties.generalCategory != .control })
        )
        switch way {
            case .none: return []
            case .bell: return [0x07]
            case .osc9: return Array("\u{1B}]9;\(kept)\u{1B}\\".utf8)
            case .kitty: return Array("\u{1B}]99;;\(kept)\u{1B}\\".utf8)
            case .osc777:
                let body = kept.replacingOccurrences(of: ";", with: ",")
                return Array("\u{1B}]777;notify;ask;\(body)\u{1B}\\".utf8)
        }
    }
}
