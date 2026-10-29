internal import AppKit
internal import UniformTypeIdentifiers

/// Opens a link the person clicked (roadmap 0075), through `NSWorkspace`, the system's own way to open a document, a folder, a page or a
/// new mail in the app the person chose for it. A click is the person's, but the text is often the model's: a file that would run (an
/// app, a script, an executable, an installer) is only shown in the Finder, and only web, mail and file links are followed, never a
/// scheme that makes another app act (`x-apple.systempreferences:`, `vscode://`).
enum LinkOpener {
    /// What a click on a link does.
    enum Action: Sendable, Equatable {
        /// Opens it in its app.
        case open(URL)
        /// Selects it in the Finder, without opening it.
        case reveal(URL)
        /// Nothing: a scheme that is not followed, or a file that is not there.
        case refuse
    }

    /// What clicking `uri` does.
    static func action(for uri: String) -> Action {
        guard let url = URL(string: uri), let scheme = url.scheme?.lowercased() else { return .refuse }
        switch scheme {
            case "http", "https", "mailto": return url.host() != nil || scheme == "mailto" ? .open(url) : .refuse
            case "file": return fileAction(url)
            default: return .refuse
        }
    }

    /// Carries out the click on `uri`.
    /// - Returns: what to tell the person when nothing was opened, or nil.
    static func perform(_ uri: String) -> String? {
        switch action(for: uri) {
            case .open(let url):
                return NSWorkspace.shared.open(url) ? nil : "Nothing opened \(url.absoluteString)."
            case .reveal(let url):
                NSWorkspace.shared.activateFileViewerSelecting([url])
                return "Shown in the Finder, not opened: it would run."
            case .refuse:
                return "Not opened: only web, mail and file links open, and only files that are there."
        }
    }

    private static func fileAction(_ url: URL) -> Action {
        let path = url.path(percentEncoded: false)
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory) else { return .refuse }
        let file = URL(fileURLWithPath: path)
        if let type = try? file.resourceValues(forKeys: [.contentTypeKey]).contentType, Self.runs(type) {
            return .reveal(file)
        }
        if !isDirectory.boolValue, FileManager.default.isExecutableFile(atPath: path) { return .reveal(file) }
        return .open(file)
    }

    /// Whether a document of `type` would run something when opened.
    private static func runs(_ type: UTType) -> Bool {
        let running: [UTType] =
            [.application, .applicationBundle, .executable, .script, .unixExecutable]
            + [UTType("com.apple.installer-package-archive"), UTType("com.apple.automator-workflow")].compactMap(\.self)
        return running.contains { type.conforms(to: $0) }
    }
}
