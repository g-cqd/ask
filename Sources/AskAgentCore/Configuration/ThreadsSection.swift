/// The `threads` section of a configuration file (roadmap 0195): how many threads may work at once, how deep they nest, and how they
/// are named.
public struct ThreadsSection: Sendable, Equatable, CustomStringConvertible, LayeredSection {
    /// How a thread is named.
    public enum Names: String, Sendable, Equatable, CaseIterable {
        /// By Apple's on-device model, from its task, where it is available; `thread-N` elsewhere.
        case onDevice
        /// `thread-N`.
        case numbered
        /// By a provider's model (`threads.namesModel`, else the conversation's own), from its task.
        case model
    }

    /// `threads.max`: how many threads may work at once; `/thread` past it is refused.
    public var max: Int?
    /// `threads.depth`: how deep threads may nest; `/thread` in a thread that deep is refused.
    public var depth: Int?
    /// `threads.names`: how a thread is named.
    public var names: Names?
    /// `threads.mergedShownFor`: how long a merged thread stays in the sidebar, as written (`"30m"`, `"2h"`, `"1d"`, `"always"`).
    public var mergedShownFor: String?
    /// `threads.questions`: where a thread's question appears while the person is elsewhere, as written.
    public var questions: String?
    /// `threads.questionsAfter`: how long `after` waits, as written (`"30s"`, `"2m"`).
    public var questionsAfter: String?
    /// `threads.namesModel`: the model `names` `"model"` asks, as `/model` takes it (`"provider/model"` or a model); nil for the conversation's.
    public var namesModel: String?
    /// `threads.summaryInstructions`: what a thread's merge asks for beside the standard summary instruction.
    public var summaryInstructions: String?
    /// `threads.model`: the model threads work with, as `/model` reads its word; nil for the conversation's.
    public var model: String?

    /// Where a thread's question appears while the person is elsewhere (note n19).
    public enum Questions: Sendable, Equatable {
        case focus
        case after(Duration)
        case lane
    }

    public static let defaultMax = 4
    public static let defaultDepth = 3
    static let mostAtOnce = 16
    static let deepest = 8

    public init(max: Int? = nil, depth: Int? = nil, names: Names? = nil) {
        self.max = max
        self.depth = depth
        self.names = names
    }

    /// The keys, in the order they are shown.
    public static let keys = [
        "max", "depth", "names", "mergedShownFor", "questions", "questionsAfter", "namesModel", "summaryInstructions",
        "model"
    ]

    public var atOnce: Int { max ?? Self.defaultMax }
    public var nesting: Int { depth ?? Self.defaultDepth }
    public var naming: Names { names ?? .onDevice }
    /// What the merge asks beyond its standard instruction; nil when nothing is written.
    public var summaryAddition: String? { Self.written(summaryInstructions) }
    /// The model threads work with and write their summaries with; nil for the conversation's own.
    public var threadModel: String? { Self.written(model) }

    /// The model that names threads under `names` `"model"`; nil for the conversation's own.
    public var namingModel: String? { Self.written(namesModel) }

    /// `text` without the white space around it; nil when nothing is left.
    private static func written(_ text: String?) -> String? {
        let kept = (text ?? "").drop { $0.isWhitespace }.reversed().drop { $0.isWhitespace }.reversed()
        return kept.isEmpty ? nil : String(kept)
    }
    /// Where a thread's question appears.
    public var whereQuestions: Questions {
        switch questions {
            case "lane": return .lane
            case "after":
                let wait = questionsAfter.flatMap { Self.duration($0) ?? nil } ?? .seconds(30)
                return .after(wait)
            default: return .focus
        }
    }

    /// The words `threads.questions` takes.
    static let questionWords = ["focus", "after", "lane"]

    /// How long a merged thread stays listed; nil for always.
    public var mergedListing: Duration? {
        guard let written = mergedShownFor else { return .seconds(86_400) }
        return Self.duration(written) ?? .seconds(86_400)
    }

    /// `"30s"`, `"30m"`, `"2h"` or `"1d"` as a duration, `"always"` as nil (`.some(nil)`); nil when it is neither.
    static func duration(_ written: String) -> Duration?? {
        if written == "always" { return .some(nil) }
        let units: [Character: Int64] = ["s": 1, "m": 60, "h": 3_600, "d": 86_400]
        guard let unit = written.last.flatMap({ units[$0] }), let count = Int64(written.dropLast()), count > 0 else {
            return nil
        }
        // @dl:accept -- every section layers its keys this way; the key lists are the data
        return .some(.seconds(count * unit))
    }

    /// `self` with every key `section` sets replaced.
    // @dl:accept -- each section layers its keys the same way; the key lists are the data
    public func layered(with section: ThreadsSection) -> ThreadsSection {
        var merged = ThreadsSection(
            // @dl:accept -- every section layers its keys this way; the key lists are the data
            max: section.max ?? max,
            depth: section.depth ?? depth,
            names: section.names ?? names
        )
        // @dl:accept -- every section layers its keys this way; the key lists are the data
        merged.mergedShownFor = section.mergedShownFor ?? mergedShownFor
        merged.questions = section.questions ?? questions
        merged.questionsAfter = section.questionsAfter ?? questionsAfter
        merged.namesModel = section.namesModel ?? namesModel
        merged.summaryInstructions = section.summaryInstructions ?? summaryInstructions
        merged.model = section.model ?? model
        return merged
    }

    /// The value of `key` (one of `keys`) as a file writes it, or nil when this section does not set it.
    public func value(forKey key: String) -> String? {
        switch key {
            case "max": max.map(String.init)
            case "depth": depth.map(String.init)
            case "names": names?.rawValue
            case "mergedShownFor": mergedShownFor
            case "questions": questions
            case "questionsAfter": questionsAfter
            case "namesModel": namesModel
            case "summaryInstructions": summaryInstructions
            case "model": model
            default: nil
        }
    }

    public var description: String { SectionText.describe(Self.keys, value(forKey:)) }
}
