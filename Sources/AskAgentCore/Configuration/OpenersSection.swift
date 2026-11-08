/// `openers` (roadmap 0216, ADR-0148): the app a clicked link opens in, per kind of link, and rules that match links to an app or a
/// command. Only the person's own configuration file may set it.
public struct OpenersSection: Sendable, Equatable, LayeredSection {
    /// The keys the section takes.
    public static let keys = ["file", "folder", "web", "rules"]

    /// An app's name or bundle identifier for each kind of link; nil for the system's choice.
    public var file: String?
    public var folder: String?
    public var web: String?
    /// The rules, the first that matches winning, before the kinds.
    public var rules: [OpenerRule]?

    public init(file: String? = nil, folder: String? = nil, web: String? = nil, rules: [OpenerRule]? = nil) {
        self.file = file
        self.folder = folder
        self.web = web
        self.rules = rules
    }

    /// `self` with every key `section` sets replaced.
    public func layered(with section: OpenersSection) -> OpenersSection {
        OpenersSection(
            file: section.file ?? file,
            folder: section.folder ?? folder,
            web: section.web ?? web,
            rules: section.rules ?? rules
        )
    }
}
