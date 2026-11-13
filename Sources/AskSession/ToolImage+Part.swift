internal import AskAI
internal import AskTUI

extension ToolImage {
    /// The picture as a request carries it.
    var part: ImagePart { ImagePart(mediaType: mediaType, data: data) }

    /// A picture a session kept, as the screen shows it.
    init(_ part: ImagePart) { self.init(mediaType: part.mediaType, data: part.data) }
}
