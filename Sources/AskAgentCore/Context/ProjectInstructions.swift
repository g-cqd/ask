internal import Foundation

/// The instruction files projects carry for coding agents (`AGENTS.md`, or `CLAUDE.md` where there is no
/// `AGENTS.md`), found the way a project expects: ask's global file first, then each directory from the home
/// directory down to the working directory, so nearer files come last and take precedence.
///
/// Outside the home directory only the working directory itself is read, so a checkout under `/tmp` does not
/// pick up a stray file from `/`. Files are capped; a binary file is skipped with a reason, never read as text.
public enum ProjectInstructions {
    /// One instruction file.
    public struct File: Sendable, Equatable {
        public let path: String
        /// The file's text, possibly truncated; empty when skipped.
        public let text: String
        /// Why the file was not used, when it was not.
        public let skippedBecause: String?
    }

    /// The most bytes read from one file.
    public static let maximumBytes = 64 << 10
    /// Appended to a file cut at ``maximumBytes``.
    public static let truncationNote = "\n\n[ask: this file was truncated at 64 KiB]"

    static let names = ["AGENTS.md", "CLAUDE.md"]

    /// The instruction files for `workingDirectory`, outermost first.
    public static func discover(from workingDirectory: String, home: String, configDirectory: String) -> [File] {
        var found: [File] = []
        if let global = read(configDirectory + "/AGENTS.md") { found.append(global) }
        for directory in directories(from: workingDirectory, home: home) {
            if let file = names.lazy.compactMap({ read(directory + "/" + $0) }).first { found.append(file) }
        }
        return found
    }

    /// The files as prompt blocks, each naming its source. Skipped files produce none.
    public static func promptBlocks(_ files: [File]) -> [String] {
        files.filter { $0.skippedBecause == nil && !$0.text.isEmpty }
            .map { "Instructions from \($0.path):\n\n\($0.text)" }
    }

    /// From the home directory (inclusive) down to `workingDirectory`, or only `workingDirectory` outside home.
    private static func directories(from workingDirectory: String, home: String) -> [String] {
        let start = URL(fileURLWithPath: workingDirectory).standardizedFileURL.path
        let top = URL(fileURLWithPath: home).standardizedFileURL.path
        guard start == top || start.hasPrefix(top + "/") else { return [start] }
        var chain = [start]
        var current = start
        while current != top {
            current = (current as NSString).deletingLastPathComponent
            chain.append(current)
        }
        return chain.reversed()
    }

    private static func read(_ path: String) -> File? {
        guard let data = FileManager.default.contents(atPath: path) else { return nil }
        let bytes = [UInt8](data.prefix(maximumBytes))
        guard !bytes.contains(0), var text = String(validating: bytes, as: UTF8.self) ?? decodeCut(bytes) else {
            return File(path: path, text: "", skippedBecause: "not UTF-8 text")
        }
        if data.count > maximumBytes { text += truncationNote }
        return File(path: path, text: text, skippedBecause: nil)
    }

    /// A prefix cut at the byte limit may end inside a character: drop the partial character, keep the rest.
    private static func decodeCut(_ bytes: [UInt8]) -> String? {
        for drop in 1 ... 3 where bytes.count > drop {
            if let text = String(validating: bytes.dropLast(drop), as: UTF8.self) { return text }
        }
        return nil
    }
}
