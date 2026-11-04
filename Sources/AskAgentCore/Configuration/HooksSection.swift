/// The `hooks` section of a configuration file (roadmap 0192, ADR-0143). `maxContinues` only from the person's own file; the check and its
/// deadline also from a trusted project's, since the right command is the repository's.
public struct HooksSection: Sendable, Equatable, CustomStringConvertible, LayeredSection {
    /// `hooks.maxContinues`: how many times hooks may continue one run that would have ended; each also counts against the turn limit.
    public var maxContinues: Int?
    /// `hooks.check`: a command run when a run that changed things would end (``CheckHook``); its failure is sent back to the model.
    public var check: String?
    /// `hooks.checkTimeout`: how many seconds the check may take before it is stopped and the run simply ends.
    public var checkTimeout: Int?

    /// How many times when nothing says (the owner's choice, 2026-11-02).
    public static let defaultMaxContinues = 3
    /// The most a file may ask for.
    static let mostContinues = 100
    /// The check's deadline when nothing says, and the most: the `bash` tool's own limit (the owner's choice, 2026-11-02).
    public static let defaultCheckSeconds = 600

    // @dl:accept -- every section of the file is decoded and layered by the same idiom; its keys are the data
    public init(maxContinues: Int? = nil, check: String? = nil, checkTimeout: Int? = nil) {
        self.maxContinues = maxContinues
        self.check = check
        self.checkTimeout = checkTimeout
    }

    /// The keys, in the order they are shown.
    public static let keys = ["maxContinues", "check", "checkTimeout"]

    /// How many continues a run is allowed.
    public var continues: Int { maxContinues ?? Self.defaultMaxContinues }
    /// How long the check may take.
    // @dl:accept -- every section of the file is decoded and layered by the same idiom; its keys are the data
    public var checkSeconds: Int { checkTimeout ?? Self.defaultCheckSeconds }

    /// `self` with every key `section` sets replaced.
    // @dl:accept -- each section layers its keys the same way; the key lists are the data
    public func layered(with section: HooksSection) -> HooksSection {
        HooksSection(
            // @dl:accept -- every section layers its keys this way; the key lists are the data
            maxContinues: section.maxContinues ?? maxContinues,
            check: section.check ?? check,
            checkTimeout: section.checkTimeout ?? checkTimeout
        )
    }

    /// The value of `key` (one of `keys`) as a file writes it, or nil when this section does not set it.
    public func value(forKey key: String) -> String? {
        switch key {
            case "maxContinues": maxContinues.map(String.init)
            case "check": check
            case "checkTimeout": checkTimeout.map(String.init)
            default: nil
        }
    }

    public var description: String { SectionText.describe(Self.keys, value(forKey:)) }
}
