internal import AskAI
internal import AskTUI
internal import AskTools
internal import Synchronization

/// A picture the person pasted (roadmap 0224; the owner, 2026-11-06 and 2026-11-12): refused, with the reason, when the model takes
/// none; otherwise bounded as the read tool bounds one, and that is what is attached and sent.
extension AgentConversation {
    func preparePicture(_ bytes: [UInt8]) async -> PicturePreparation {
        let model = current.withLock { $0.settings.model }
        switch model.acceptsImages {
            case false?: return .refused("\(model.model) does not take images")
            case nil:
                return .refused(
                    "it is not known that \(model.model) takes images; \"images\": true on the model in providers.json says so"
                )
            case true?: break
        }
        switch PastedImage.bounded(bytes, limits: model.imageLimits) {
            case .success(let part): return .ready(ToolImage(mediaType: part.mediaType, data: part.data))
            case .failure(let refusal): return .refused(refusal.description)
        }
    }
}
