internal import AemiJSON
internal import Foundation

extension ImagePart {
    /// The picture as Gemini's `inlineData` part: `{"inlineData":{"mimeType":…,"data":…}}`.
    func writeInline(into writer: inout JSONStreamWriter) {
        writer.object { writeInlineFields(into: &$0) }
    }

    /// The `inlineData` field alone, for a part object the caller has opened.
    func writeInlineFields(into writer: inout JSONStreamWriter) {
        writer.key("inlineData")
        writer.object { writer in
            writer.field("mimeType", mediaType)
            writer.field("data", Data(data).base64EncodedString())
        }
    }
}
