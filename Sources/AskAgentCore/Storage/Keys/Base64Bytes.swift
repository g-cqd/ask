internal import Foundation

/// Bytes written in JSON as one base64 string, whatever the encoder does with `Data` by itself.
struct Base64Bytes: Codable, Equatable {
    let data: Data

    init(_ data: Data) { self.data = data }

    init(_ bytes: [UInt8]) { data = Data(bytes) }

    init(from decoder: any Decoder) throws {
        let text = try decoder.singleValueContainer().decode(String.self)
        guard let data = Data(base64Encoded: text) else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "not base64"))
        }
        self.data = data
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(data.base64EncodedString())
    }
}
