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
        /// A picture's bytes (roadmap 0224): a copied image file's, or the pasteboard's PNG or TIFF.
        case picture([UInt8])
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

    /// The files `pasteboard` holds, copied in Finder or another file manager; empty for none.
    static func files(on pasteboard: NSPasteboard) -> [URL] {
        pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
    }

    /// The picture `pasteboard` holds: the first of `files` named as one, or, when no file was copied, its PNG or TIFF data (a
    /// copied file's TIFF is its icon); nil for none.
    static func picture(on pasteboard: NSPasteboard, files: [URL]) -> [UInt8]? {
        if let file = files.first(where: { PastedPath.extensions.contains($0.pathExtension.lowercased()) }),
            let data = FileManager.default.contents(atPath: file.path)
        {
            return [UInt8](data)
        }
        guard files.isEmpty else { return nil }
        for type in [NSPasteboard.PasteboardType.png, .tiff] {
            if let data = pasteboard.data(forType: type), !data.isEmpty { return [UInt8](data) }
        }
        return nil
    }

    /// The text `pasteboard` holds, unless the person has denied this program access to it.
    static func read(from pasteboard: NSPasteboard) -> Reading {
        if pasteboard.accessBehavior == .alwaysDeny {
            return .denied(
                "Paste refused: pasteboard access is denied for this terminal in System Settings, Privacy & Security."
            )
        }
        // A picture wins over the text it carries (the owner, 2026-11-12): a copied image file first, as Finder puts its icon
        // beside it, then the picture itself.
        let files = files(on: pasteboard)
        if let bytes = picture(on: pasteboard, files: files) { return .picture(bytes) }
        // A copied file is its full path, not the name its text holds (the owner, 2026-11-21).
        if let paths = PastedPath.typed(files.map(\.path)) { return .text(paths) }
        guard let text = pasteboard.string(forType: .string), !text.isEmpty else { return .empty }
        return .text(text)
    }
}
