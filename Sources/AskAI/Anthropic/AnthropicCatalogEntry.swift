/// The native model descriptor fields observed from Anthropic's model API. Capability flags are reports, not an
/// exhaustive statement of compatibility: Sonnet 5.5 accepts legacy enabled thinking while reporting it unsupported.
struct AnthropicCatalogEntry: Decodable {
    let id: String?
    let maxInput: Lenient<Int>?
    let maxOutput: Lenient<Int>?
    let capabilities: Lenient<Capabilities>?

    struct Support: Decodable { let supported: Lenient<Bool>? }
    struct Thinking: Decodable {
        let supported: Lenient<Bool>?
        let types: Lenient<[String: Lenient<Support>]>?
    }
    struct Capabilities: Decodable {
        let thinking: Lenient<Thinking>?
        let effort: Lenient<[String: Lenient<Support>]>?
    }

    enum CodingKeys: String, CodingKey {
        case id, capabilities
        case maxInput = "max_input_tokens"
        case maxOutput = "max_tokens"
    }

    /// A usable descriptor, leaving absent or malformed optional fields unknown.
    var model: CatalogModel? {
        guard let id, CatalogModel.validID(id) else { return nil }
        let thinking = capabilities?.value?.thinking?.value
        let modes = ThinkingMode.allCases.filter {
            thinking?.types?.value?[$0.rawValue]?.value?.supported?.value == true
        }
        let flags = capabilities?.value?.effort?.value ?? [:]
        let reported = flags.keys.filter { CatalogModel.validLevel($0) && flags[$0]?.value?.supported?.value == true }
        let order = ["minimal", "low", "medium", "high", "xhigh", "max", "ultra"]
        let levels = reported.sorted {
            let left = order.firstIndex(of: $0) ?? order.count
            let right = order.firstIndex(of: $1) ?? order.count
            return left == right ? $0 < $1 : left < right
        }
        return CatalogModel(
            id: id, contextWindow: maxInput?.value.flatMap(Self.limit),
            maxOutputTokens: maxOutput?.value.flatMap(Self.limit),
            reasoningLevels: levels.count <= CatalogModel.levelLimit ? levels : [],
            supportsThinking: thinking?.supported?.value, thinkingModes: modes)
    }

    /// A generous safety bound, not a claimed provider limit. Never size a run from a hostile or nonsensical integer.
    private static func limit(_ number: Int) -> Int? { (1 ... 100_000_000).contains(number) ? number : nil }
}
