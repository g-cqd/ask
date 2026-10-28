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
        writer.object { writer in
            writer.field("role", "user")
            writer.key("content")
            writer.array { parts in
                parts.typed(wire == .chat ? "text" : "input_text", "text", attachedLead)
                for image in images {
                    parts.object {
                        switch wire {
                            case .chat:
                                $0.field("type", "image_url")
                                $0.key("image_url")
                                $0.object { $0.field("url", image.dataURL) }
                            case .responses:
                                $0.field("type", "input_image")
                                $0.field("image_url", image.dataURL)
                        }
                    }
                }
            }
        }
    }
}
