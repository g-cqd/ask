public import AskAI
internal import FoundationModels

/// Apple's on-device language model, the one `SystemLanguageModel.default` names. It is linked, not launched: no helper is compiled,
/// no process is started, no file is cached and executed (ADR-0116).
public enum AppleModel {
    /// The name ask calls the provider by.
    public static let provider = ProviderSettings.apple
    /// The model id: there is one on-device model.
    public static let id = ProviderSettings.appleModel
    /// The window when the system will not say: the figure Apple documents for the on-device model.
    public static let fallbackContextWindow = 4096
    /// The most it is asked to write in a reply, which a window this small cannot spare more for.
    public static let maximumOutputTokens = 1024

    /// Whether the model can answer right now, and if not, why in words a person can act on.
    public enum Availability: Sendable, Equatable {
        case available
        case unavailable(reason: String)

        public var isAvailable: Bool { self == .available }
    }

    /// What the system says about the model. A property read, no model is loaded.
    public static func availability() -> Availability {
        switch SystemLanguageModel.default.availability {
            case .available: .available
            case .unavailable(.deviceNotEligible):
                .unavailable(reason: "this Mac is not eligible for Apple Intelligence")
            case .unavailable(.appleIntelligenceNotEnabled):
                .unavailable(reason: "Apple Intelligence is off: turn it on in System Settings")
            case .unavailable(.modelNotReady): .unavailable(reason: "the model is still downloading")
            case .unavailable: .unavailable(reason: "the model is unavailable")
        }
    }

    /// The context window the system reports, else ``fallbackContextWindow``.
    public static var contextWindow: Int { Swift.max(1, SystemLanguageModel.default.contextSize) }

    /// Which variant of Apple's model this Mac runs (`AFM 3 Core Advanced`), from macOS 27; nil before. The system picks it by hardware and offers no
    /// way to choose another, so there is one local chat model per Mac and this names it (ADR-0120).
    public static var variantName: String? {
        if #available(macOS 27.0, *) { return SystemLanguageModel.default.variant.displayName }
        return nil
    }

    /// The model as a catalog entry, for the model list and for sizing a run.
    public static var catalogEntry: CatalogModel {
        CatalogModel(
            id: id, contextWindow: contextWindow, maxOutputTokens: maximumOutputTokens, supportsThinking: false)
    }
}
