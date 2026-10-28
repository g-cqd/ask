internal import AppKit

/// The host's pasteboard, through `NSPasteboard` (roadmap 0082), still the system pasteboard API on macOS 27; SwiftUI's clipboard
/// modifiers sit on top of it and need views and menu commands, which a terminal program has not.
///
/// Since macOS's pasteboard privacy (AppKit updates, 2025), reading the general pasteboard from code may ask the person first, unless the
/// person denied it for good. ask reads only when the terminal passed Command+V or Ctrl+V on instead of pasting, and checks
/// `accessBehavior` first so that a denial is said, not silent. Writing is not covered by the alert. The first use costs about 1 MiB and
/// 2 ms (measured 2026-10-28), and nothing before it.
enum HostPasteboard {
    /// What a paste read: the text, nothing to paste, or a refusal to say.
    enum Reading: Sendable, Equatable {
        case text(String)
        case empty
        case denied(String)
    }

    /// Writes `text` to the general pasteboard.
    static let write: @Sendable (String) async -> PasteboardResult = { text in
        write(text, to: NSPasteboard.general)
    }

    /// Reads the general pasteboard's text.
    static let read: @Sendable () async -> Reading = { read(from: NSPasteboard.general) }

    /// Replaces what `pasteboard` holds with `text`.
    static func write(_ text: String, to pasteboard: NSPasteboard) -> PasteboardResult {
        _ = pasteboard.prepareForNewContents(with: [])
        return pasteboard.setString(text, forType: .string) ? .copied : .failed("the pasteboard refused the text")
    }

    /// The text `pasteboard` holds, unless the person has denied this program access to it.
    static func read(from pasteboard: NSPasteboard) -> Reading {
        if pasteboard.accessBehavior == .alwaysDeny {
            return .denied(
                "Paste refused: pasteboard access is denied for this terminal in System Settings, Privacy & Security.")
        }
        guard let text = pasteboard.string(forType: .string), !text.isEmpty else { return .empty }
        return .text(text)
    }
}
