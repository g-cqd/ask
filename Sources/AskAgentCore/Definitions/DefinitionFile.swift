internal import AemiFrontMatter

/// A definition file read for what it holds, never rejected for how it is written: a skill's `SKILL.md`, or an agent definition in any harness's format.
///
/// Reading cannot fail. It returns the fields it understood, the comments that look like `key: value`, the body, and a list of things it noticed;
/// a file that is not what it expected yields fewer fields and more diagnostics, never an error (roadmap 0061). The shapes it accepts are the
/// ones found in real harness directories: YAML or TOML fences, a bare TOML file, no head at all, quoted and block scalars, flow and block lists,
/// nested maps, comments, byte-order marks, CRLF, and keys spelled in any case or style.
public struct DefinitionFile: Sendable, Equatable {
    /// How the head was written.
    public enum Format: Sendable, Equatable {
        case yaml
        case toml
        /// No head: the whole text is the body.
        case none
    }

    public internal(set) var format = Format.none
    /// The keys, as written and in order. A key written twice appears once, with the last value, and the repeat is a diagnostic.
    public internal(set) var entries: [DefinitionEntry] = []
    /// Comments of the form `# key: value` or `# key = value`, which some harnesses use to carry a setting another harness would ignore
    /// (`# fallback_models: a, b`). Kept as entries; no one is told they are there unless they ask.
    public internal(set) var hints: [DefinitionEntry] = []
    /// What follows the head.
    public internal(set) var body = ""
    /// What was noticed and tolerated.
    public internal(set) var diagnostics: [String] = []
    /// Whether the head's closing fence was not found, so its end was guessed.
    public internal(set) var isUnterminated = false

    /// Reads `text`. `isTOML` says the whole file is TOML, as Codex's and Vibe's agent files are (they have no fences).
    public init(parsing text: String, isTOML: Bool = false) {
        let bytes = Array(text.utf8)
        if isTOML {
            format = .toml
            (entries, hints, diagnostics) = DefinitionReader.toml(bytes)
            return
        }
        guard let head = FrontMatter(in: bytes, options: DefinitionReader.headOptions) else {
            body = Self.normalized(bytes.starts(with: [0xEF, 0xBB, 0xBF]) ? bytes[3...] : bytes[...])
            return
        }
        format = head.format == .toml ? .toml : .yaml
        isUnterminated = !head.isClosed
        body = Self.normalized(bytes[head.bodyStart...])
        (entries, hints, diagnostics) = DefinitionReader.read(head, in: bytes)
    }

    /// Text with every kind of line ending read as one.
    private static func normalized(_ bytes: ArraySlice<UInt8>) -> String {
        let text = String(decoding: bytes, as: UTF8.self)
        // Almost no file has a carriage return, and replacing in a text that has none still walks all of it.
        guard bytes.contains(0x0D) else { return text }
        return text.replacing("\r\n", with: "\n").replacing("\r", with: "\n")
    }
}
