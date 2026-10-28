internal import AskAI
internal import AskMCP
internal import Foundation

/// The pictures in a server's tool result, made fit to send like those `read` gives (roadmap 0084).
///
/// A server is not trusted: the declared type is ignored, the bytes are sniffed and decoded, and every picture is bounded and
/// re-encoded the same way. What cannot be shown is said in the result's text, and never pasted.
struct MCPResultImages {
    /// The most pictures one result may give; the rest are named.
    static let maximum = ReadTool.defaultImages

    /// The pictures that were made fit, in order.
    var parts: [ImagePart] = []
    /// For each block of the result that is an image, the line that stands for it in the text.
    var lines: [Int: String] = [:]

    /// Reads the images of `result`.
    /// - Parameters:
    ///   - result: what the server returned.
    ///   - allowance: what the model's provider accepts.
    init(_ result: MCPToolResult, allowance: ImageReader.Allowance) {
        for (index, block) in result.content.enumerated() {
            guard case .image(let declared, let base64) = block else { continue }
            lines[index] = line(declared: declared, base64: base64, allowance: allowance)
        }
    }

    private mutating func line(declared: String, base64: String, allowance: ImageReader.Allowance) -> String {
        guard parts.count < Self.maximum else {
            return "[image \(declared): not shown, over the \(Self.maximum) a result may show]"
        }
        guard base64.utf8.count / 4 * 3 <= FileTools.maximumMediaBytes,
            let data = Data(base64Encoded: base64, options: .ignoreUnknownCharacters)
        else { return "[image \(declared): not shown, it is too large or is not valid base64]" }
        do {
            let result = try ImageReader.read([UInt8](data), allowance: allowance)
            parts.append(result.part)
            return "[\(result.summary): shown]"
        } catch {
            return "[image \(declared), \(data.count) bytes: not shown, \(Self.reason(error))]"
        }
    }

    private static func reason(_ error: ImageReader.Failure) -> String {
        switch error {
            case .notAnImage: "the bytes are not an image ask knows"
            case .animated: "it is an animated PNG"
            case .undecodable: "it could not be decoded"
            case .cannotFit: "it could not be made small enough to send"
        }
    }
}
