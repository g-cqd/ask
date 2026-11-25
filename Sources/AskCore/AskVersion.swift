/// `ask`'s release version: one source of truth for `--version`, `ask serve` (ACP), MCP client identity, and HTTP
/// `User-Agent` headers.
///
/// The `swift-ci` release workflow checks that `ask --version` matches the pushed `v*` tag (without the leading `v`)
/// before signing, notarising, and publishing the release archive.
public enum AskVersion {
    /// Semantic version string reported by `ask --version` (and matched against `v<version>` release tags).
    public static let current = "0.1.0-alpha.1"
}
