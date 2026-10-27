/// One event of a Responses stream, with the fields ask reads. A field a server leaves out is nil: llama.cpp sends no
/// `output_index`, and only OpenAI sends summaries and encrypted reasoning.
struct ResponsesWireEvent: Decodable, Sendable {
    let type: String
    let itemID: String?
    let outputIndex: Int?
    let delta: String?
    let item: Item?
    let response: Response?
    /// An `error` event's own code and message.
    let code: OpenAIWireChunk.Code?
    let message: String?

    enum CodingKeys: String, CodingKey {
        case type, delta, item, response, code, message
        case itemID = "item_id"
        case outputIndex = "output_index"
    }

    /// Text in a summary, a reasoning content part or a message part.
    struct Part: Decodable, Sendable {
        let type: String?
        let text: String?
    }

    struct Item: Decodable, Sendable {
        let type: String
        let id: String?
        let callID: String?
        let name: String?
        let arguments: String?
        let summary: [Part]?
        let content: [Part]?
        let encryptedContent: String?

        enum CodingKeys: String, CodingKey {
            case type, id, name, arguments, summary, content
            case callID = "call_id"
            case encryptedContent = "encrypted_content"
        }
    }

    struct Response: Decodable, Sendable {
        let id: String?
        let model: String?
        let status: String?
        let output: [Item]?
        let usage: ReportedUsage?
        let error: ErrorBody?
        let incompleteDetails: Incomplete?

        enum CodingKeys: String, CodingKey {
            case id, model, status, output, usage, error
            case incompleteDetails = "incomplete_details"
        }
    }

    struct Incomplete: Decodable, Sendable {
        let reason: String?
    }

    struct ErrorBody: Decodable, Sendable {
        let code: OpenAIWireChunk.Code?
        let message: String?
        let type: String?
    }
}
