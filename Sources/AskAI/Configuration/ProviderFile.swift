internal import AemiJSON
internal import Foundation

/// Adds an OpenAI-compatible endpoint to `providers.json` so `ask login custom` can name one without the user editing a file. The key never
/// goes in it: it is stored with the other credentials, and the entry holds only where the server is and what it speaks.
///
/// What the file already holds is carried over byte for byte: every other member, and every other provider, is written back exactly as
/// it was read, so nothing the person wrote is reformatted or lost.
public enum ProviderFile {
    /// Why an endpoint could not be added.
    public enum Failure: Error, CustomStringConvertible, Equatable {
        case invalidName
        case reservedName(String)
        case refusedEndpoint(String)
        case unreadable(String)
        case io(Int32)

        public var description: String {
            switch self {
                case .invalidName:
                    "the name must be lower-case letters, digits, '.', '_' or '-', starting with a letter or digit"
                // @dl:accept -- diagnostic sentences are independent data, shared with no other error enum
                case .reservedName(let name): "\(name) is a built-in provider; choose another name"
                case .refusedEndpoint(let reason): "the address is refused: \(reason)"
                case .unreadable(let why): "providers.json was left alone because it \(why)"
                case .io(let code): "providers.json could not be written (error \(code))"
            }
        }
    }

    /// Adds, or replaces, the endpoint `name` at `baseURL`, in the file at `path`.
    /// - Parameters:
    ///   - name: the endpoint's name, as `--provider` will say it.
    ///   - baseURL: where the server answers, without a trailing slash.
    ///   - responses: whether the server speaks the Responses API rather than chat completions.
    ///   - path: the `providers.json` to change.
    /// - Returns: the name as stored.
    /// - Throws: a ``Failure``; the file is untouched when it is thrown.
    @discardableResult
    public static func addEndpoint(
        name: String, baseURL: String, responses: Bool = false, at path: String
    ) throws(Failure) -> String {
        let lowered = name.lowercased()
        guard PlainToken.word(lowered, length: 1 ... 64, lowercase: true) else { throw .invalidName }
        let reserved = [
            ProviderSettings.anthropic, ProviderSettings.codex, ProviderSettings.agy, ProviderSettings.apple, "claude"
        ]
        guard !reserved.contains(lowered), ProviderPreset.named(lowered) == nil else { throw .reservedName(lowered) }
        let trimmed = baseURL.hasSuffix("/") ? String(baseURL.dropLast()) : baseURL
        guard let url = URL(string: trimmed) else { throw .refusedEndpoint("it is not a URL") }
        if let reason = EndpointPolicy.refusal(for: url, carriesCredential: true) { throw .refusedEndpoint(reason) }

        let entry = JSONStreamWriter.object(of: [
            ("api", responses ? ProviderSettings.openAIResponses : ProviderSettings.openAICompletions),
            ("baseUrl", trimmed)
        ])
        var members: [(String, [UInt8])] = []
        var providers: [(String, [UInt8])] = []
        if let existing = FileManager.default.contents(atPath: path) {
            (members, providers) = try Self.members(of: Array(existing))
        }
        providers.removeAll { $0.0 == lowered }
        providers.append((lowered, entry))
        providers.sort { $0.0 < $1.0 }
        members.removeAll { $0.0 == "providers" }
        members.append(("providers", Self.object(providers, depth: 1)))
        members.sort { $0.0 < $1.0 }
        let bytes = Self.object(members, depth: 0) + [0x0A]
        let directory = URL(fileURLWithPath: path).deletingLastPathComponent()
        do {
            try FileManager.default.createDirectory(
                at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            try AtomicFile.replace(URL(fileURLWithPath: path), with: bytes)
        } catch let failure as AtomicFile.Failure { throw .io(failure.code) } catch { throw .io(EIO) }
        return lowered
    }

    /// The file's top-level members and its providers, each value as the bytes it was written in.
    private static func members(of bytes: [UInt8]) throws(Failure) -> (
        members: [(String, [UInt8])], providers: [(String, [UInt8])]
    ) {
        guard let document = try? AemiJSON.parse(bytes, options: JSONParseOptions(recordsContainerSpans: true)),
            document.root.isObject
        else { throw .unreadable("is not a JSON object") }
        var members: [(String, [UInt8])] = []
        var providers: [(String, [UInt8])] = []
        var unreadable = false
        document.root.forEachMember { key, value in
            guard let raw = value.withRawJSONBytes({ Array($0) }) else {
                unreadable = true
                return
            }
            members.append((key, raw))
            guard key == "providers" else { return }
            guard value.isObject else {
                unreadable = true
                return
            }
            value.forEachMember { name, entry in
                if let raw = entry.withRawJSONBytes({ Array($0) }) {
                    providers.append((name, raw))
                } else {
                    unreadable = true
                }
            }
        }
        guard !unreadable else { throw .unreadable("has a value that cannot be carried over") }
        return (members, providers)
    }

    /// An object of `members`, one to a line, indented `depth` levels, each value exactly as given.
    private static func object(_ members: [(String, [UInt8])], depth: Int) -> [UInt8] {
        let indent = Array(String(repeating: "  ", count: depth + 1).utf8)
        var out: [UInt8] = Array("{".utf8)
        for (index, member) in members.enumerated() {
            out += Array((index == 0 ? "\n" : ",\n").utf8) + indent
            var key = JSONStreamWriter()
            key.string(member.0)
            out += key.finish() + Array(": ".utf8) + member.1
        }
        out += Array(("\n" + String(repeating: "  ", count: depth) + "}").utf8)
        return members.isEmpty ? Array("{}".utf8) : out
    }
}
