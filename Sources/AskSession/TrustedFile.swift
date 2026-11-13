internal import AskAgentCore
internal import Foundation

/// One file of a project's that trust is given or taken from by name (`ask trust --skills`, `--agents`): what it is called, where it
/// is, the digest of its bytes now, and what it says it is for, which the person is shown before it is trusted.
package struct TrustedFile {
    let name: String
    /// Shown after the name: where it comes from, for a skill.
    let origin: String?
    let file: String
    let realFile: String
    let digest: String
    let description: String

    /// `all` narrowed to `names` (any case) when there are any, and the names nothing answered.
    static func narrowed<Item>(_ all: [Item], to names: [String], name: (Item) -> String) -> (
        found: [Item], missing: [String]
    ) {
        guard !names.isEmpty else { return (all, []) }
        let wanted = Set(names.map { $0.lowercased() })
        let found = all.filter { wanted.contains(name($0).lowercased()) }
        let present = Set(found.map { name($0).lowercased() })
        return (found, names.filter { !present.contains($0.lowercased()) })
    }

    /// Trusts `files` as they are now, or forgets them, in the store at `path`.
    static func apply(_ files: [TrustedFile], granting: Bool, store path: String) throws(ConfigurationError) {
        var trust = try ProjectTrust.load(path)
        for file in files {
            if granting { trust.trust(file.realFile, digest: file.digest) } else { trust.untrust(file.realFile) }
        }
        try trust.save(to: path)
    }

    /// `ask trust --skills` or `--agents`: says each file and what it is for, so the person sees the words, then trusts them; says
    /// the names nothing answered, and exits 66 when there were any.
    package static func trust(
        _ found: (found: [TrustedFile], missing: [String]),
        kind: String,
        store path: String,
        footer: String
    ) {
        for name in found.missing {
            FileHandle.standardError.write(Data("ask: no project \(kind) called \(name).\n".utf8))
        }
        guard !found.found.isEmpty else { fail("ask: there are no project \(kind)s to trust.", code: 66) }
        do { try apply(found.found, granting: true, store: path) } catch { fail("ask: \(error)", code: 73) }
        for file in found.found {
            let origin = file.origin.map { " (\($0))" } ?? ""
            print("Trusted \(file.name)\(origin): \(file.file) (sha256 \(file.digest.prefix(12))…)")
            print("    \(file.description.prefix(100))")
        }
        print(footer)
        if !found.missing.isEmpty { Foundation.exit(66) }
    }

    /// `ask untrust --skills` or `--agents`.
    package static func untrust(_ found: (found: [TrustedFile], missing: [String]), kind: String, store path: String) {
        do { try apply(found.found, granting: false, store: path) } catch { fail("ask: \(error)", code: 73) }
        for file in found.found { print("No longer trusting \(file.name): \(file.file)") }
        for name in found.missing { print("No project \(kind) called \(name).") }
    }
}
