/// Pictures the person pasted (roadmap 0224), as updates bring them: one ready to attach, and those of a message replayed on resume.
extension ScreenController {
    mutating func applyPicture(_ update: ConversationUpdate) {
        switch update {
            case .pictureAttached(let image):
                // Its token where the cursor is; what the draft names when it is sent goes with it.
                state.editor.paste(PastedPictures.token(state.pictures.add(image)))
            case .promptPictures(let images) where !state.transcript.items.isEmpty:
                // Under the message just replayed, as when it was sent.
                state.transcript.toolImages[state.transcript.items.count - 1] = images
            default: break
        }
    }
}
