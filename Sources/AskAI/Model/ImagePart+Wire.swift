internal import AemiJSON

extension ImagePart {
    /// How OpenAI's two wires spell the same user message of pictures.
    enum FollowingWire {
        /// Chat completions: `{"type":"text"}` and `{"type":"image_url","image_url":{"url":…}}`.
        case chat
        /// Responses: `{"type":"input_text"}` and `{"type":"input_image","image_url":…}`.
        case responses
    }

    /// Writes the user message that carries the pictures of the tool results just written, for a wire whose tool result holds text only.
    /// Nothing is written for no images.
    static func writeFollowing(_ images: [ImagePart], as wire: FollowingWire, into writer: inout JSONStreamWriter) {
        guard !images.isEmpty else { return }
        writeUserMessage(text: attachedLead, images: images, as: wire, into: &writer)
    }

    /// Writes a user message of `text` and then `images`, as `wire` spells it (roadmap 0224: the person's pasted pictures too).
    static func writeUserMessage(
        text: String,
        images: [ImagePart],
        as wire: FollowingWire,
        into writer: inout JSONStreamWriter
    ) {
        writer.object { writer in
            writer.field("role", "user")
            writer.key("content")
            writer.array { parts in
                parts.typed(wire == .chat ? "text" : "input_text", "text", text)
                for image in images { image.write(as: wire, into: &parts) }
            }
        }
    }

    /// The picture as one content part of `wire`.
    func write(as wire: FollowingWire, into parts: inout JSONStreamWriter) {
        parts.object {
            switch wire {
                case .chat:
                    $0.field("type", "image_url")
                    $0.key("image_url")
                    $0.object {
                        $0.field("url", dataURL)
                        $0.field("detail", "auto")
                    }
                case .responses:
                    $0.field("type", "input_image")
                    $0.field("detail", "auto")
                    $0.field("image_url", dataURL)
            }
        }
    }

    /// Writes the person's message with the pictures they pasted (roadmap 0224), its `text` first; false, writing nothing, when it
    /// holds none, for the wire's own text-only message.
    static func writePasted(
        in blocks: [RequestBlock],
        text: [String],
        as wire: FollowingWire,
        into writer: inout JSONStreamWriter
    ) -> Bool {
        let pasted = blocks.compactMap { if case .image(let image) = $0 { image } else { nil } }
        guard !pasted.isEmpty else { return false }
        writeUserMessage(text: text.joined(separator: "\n\n"), images: pasted, as: wire, into: &writer)
        return true
    }
}
