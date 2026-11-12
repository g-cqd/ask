internal import Foundation

/// A picture pasted or dropped onto the input (roadmap 0224), read and prepared off the screen's thread: the conversation bounds it
/// as it will be sent, or says why it cannot be; its token then goes into the input.
extension ScreenSession {
    /// A message, started or queued, with the pictures its `[image N]` tokens name.
    func send(_ effect: ScreenController.Effect) {
        let sink = sink
        switch effect {
            case .startRun(let prompt):
                run = conversation.start(prompt, images: controller.state.pictures.images(in: prompt)) {
                    sink.yield(.update($0))
                }
            case .queuePrompt(let id, let text, let followUp):
                conversation.enqueue(
                    text,
                    images: controller.state.pictures.images(in: text),
                    id: id,
                    followUp: followUp
                )
            default: break
        }
    }

    /// What a paste the terminal passed on found: a picture to attach, or why the pasteboard could not be read.
    func pasted(_ event: ScreenEvent) {
        switch event {
            case .pasteRefused(let reason): controller.state.transcript.addNotice(reason, isError: true)
            case .pastedPicture(let bytes): attach { bytes }
            default: break
        }
    }

    func attach(_ read: @escaping @Sendable () -> [UInt8]?) {
        let (sink, conversation) = (sink, conversation)
        Task.detached(priority: .userInitiated) {
            guard let bytes = read(), !bytes.isEmpty else {
                sink.yield(.update(.notice("Picture not attached: the file could not be read.", isError: true)))
                return
            }
            switch await conversation.preparePicture(bytes) {
                case .ready(let image): sink.yield(.update(.pictureAttached(image)))
                case .refused(let reason):
                    sink.yield(.update(.notice("Picture not attached: \(reason).", isError: true)))
            }
        }
    }
}
