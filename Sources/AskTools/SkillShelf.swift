public import AskAgentCore
internal import Synchronization

/// The skills the `skill` tool serves, which a session replaces when the person trusts more while it runs (`ask trust --skills`
/// in another terminal): the tool reads it on every call, so a skill trusted since the session began loads without a restart.
public final class SkillShelf: Sendable {
    /// The group a session offers the `skill` tool in when it began with no skill, so had none (``LiveTools``).
    public static let liveGroup = "ask skills"

    private let held: Mutex<(catalog: SkillCatalog, knownSources: [String])>

    /// A shelf holding `catalog`, whose harness ids are `knownSources`.
    public init(catalog: SkillCatalog = SkillCatalog(), knownSources: [String] = []) {
        held = Mutex((catalog, knownSources))
    }

    /// The skills served now.
    public var catalog: SkillCatalog { held.withLock { $0.catalog } }

    /// The harness ids that exist, so a word in `from` can be told from a mistake.
    public var knownSources: [String] { held.withLock { $0.knownSources } }

    /// Serves `catalog` from now on.
    public func replace(_ catalog: SkillCatalog, knownSources: [String]) {
        held.withLock { $0 = (catalog, knownSources) }
    }
}
