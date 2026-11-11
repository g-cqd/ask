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
        /// Opens it in the app at this location, the person's opener (roadmap 0216).
        case openWith(URL, app: URL)
        /// The person's opener names an app that is not on this Mac.
        case missingApp(String)
    }

    /// What clicking `uri` does when the person's openers name `app` for it (roadmap 0216): what would be opened is opened in that
    /// app, found by bundle identifier or by name in the usual folders. What would run is still only shown, whatever the app: the path
    /// may be the model's, an app bundle is a folder to the Finder, and a terminal runs a script it is handed (note n33).
    static func action(for uri: String, app: String, folders: [URL] = applicationFolders) -> Action {
        let usual = action(for: uri)
        guard case .open(let target) = usual else { return usual }
        guard let found = application(named: app, folders: folders) else { return .missingApp(app) }
        return .openWith(target, app: found)
    }

    /// Where apps are looked for by name.
    static let applicationFolders = [
        "/Applications", "/Applications/Utilities", "/System/Applications", "/System/Applications/Utilities",
        NSHomeDirectory() + "/Applications"
    ]
    .map { URL(fileURLWithPath: $0, isDirectory: true) }

    /// The app `name` names: a bundle identifier the system knows, or `name.app` in one of `folders`.
    private static func application(named name: String, folders: [URL]) -> URL? {
        if let found = NSWorkspace.shared.urlForApplication(withBundleIdentifier: name) {
            return URL(fileURLWithPath: found.path(percentEncoded: false))
        }
        let bundle = name.hasSuffix(".app") ? name : name + ".app"
        guard !bundle.contains("/") else { return nil }
        return folders.map { $0.appending(path: bundle) }
            .first { FileManager.default.fileExists(atPath: $0.path(percentEncoded: false)) }
            .map { URL(fileURLWithPath: $0.path(percentEncoded: false)) }
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

    /// Carries out the click on `uri` as the person's openers say (roadmap 0216).
    /// - Returns: what to tell the person when nothing was opened, or nil.
    static func perform(_ uri: String, opening: LinkOpening) -> String? {
        switch opening {
            case .system: perform(uri)
            case .app(let name): perform(uri, app: name)
            case .refused(let reason): reason
            case .command: "Not run: commands as openers are not run yet (roadmap 0216, step 4)."
        }
    }

    /// Carries out the click on `uri`, in `app` when the person's openers name one.
    /// - Returns: what to tell the person when nothing was opened, or nil.
    static func perform(_ uri: String, app: String? = nil) -> String? {
        switch app.map({ action(for: uri, app: $0) }) ?? action(for: uri) {
            case .openWith(let url, let app):
                NSWorkspace.shared.open([url], withApplicationAt: app, configuration: NSWorkspace.OpenConfiguration())
                return nil
            case .missingApp(let name):
                return "Not opened: your openers name \(name), which is not on this Mac."
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
