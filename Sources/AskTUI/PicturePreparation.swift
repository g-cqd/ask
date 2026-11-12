/// What became of a picture the person pasted (roadmap 0224): ready to send, as it will be sent, or refused, and why.
public enum PicturePreparation: Sendable, Equatable {
    case ready(ToolImage)
    case refused(String)
}
