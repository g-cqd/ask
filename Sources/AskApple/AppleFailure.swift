internal import AskAI
internal import Foundation
internal import FoundationModels

/// The framework's failures as the provider failures the loop already knows how to answer: a window that is too small is compacted,
/// not retried, and a missing model is said once.
enum AppleFailure {
    /// What went wrong, whichever type the operating system reports it in.
    private enum Cause {
        case overflow, declined, busy, language, assets
        case other(String)
    }

    static func mapped(_ error: any Error) -> any Error {
        // From macOS 27 the framework reports a failure as a `LanguageModelError`; before, as the session's own `GenerationError`.
        if #available(macOS 27.0, *), let failure = error as? LanguageModelError {
            return Self.failure(Self.cause(of: failure))
        }
        guard let failure = error as? LanguageModelSession.GenerationError else { return error }
        return Self.failure(Self.cause(of: failure))
    }

    private static func cause(of failure: LanguageModelSession.GenerationError) -> Cause {
        switch failure {
            case .exceededContextWindowSize: .overflow
            case .guardrailViolation, .refusal: .declined
            case .rateLimited, .concurrentRequests: .busy
            case .assetsUnavailable: .assets
            case .unsupportedLanguageOrLocale: .language
            default: .other(failure.localizedDescription)
        }
    }

    @available(macOS 27.0, *)
    private static func cause(of failure: LanguageModelError) -> Cause {
        switch failure {
            case .contextSizeExceeded: .overflow
            case .guardrailViolation, .refusal: .declined
            case .rateLimited, .timeout: .busy
            case .unsupportedLanguageOrLocale: .language
            default: .other(failure.localizedDescription)
        }
    }

    private static func failure(_ cause: Cause) -> ProviderFailure {
        switch cause {
            case .overflow:
                ProviderFailure(
                    kind: .contextOverflow, message: "The conversation does not fit the on-device model's window.",
                    contextWindow: AppleModel.contextWindow)
            case .declined:
                ProviderFailure(kind: .invalidRequest, message: "The on-device model declined this request.")
            case .busy: ProviderFailure(kind: .overloaded, message: "The on-device model is busy; try again.")
            case .assets: ProviderFailure(kind: .notFound, message: "The on-device model is not ready on this Mac.")
            case .language:
                ProviderFailure(kind: .invalidRequest, message: "The on-device model does not support this language.")
            case .other(let text): ProviderFailure(kind: .other("on-device"), message: text)
        }
    }
}
