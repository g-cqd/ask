public import AskAI

/// A picture the person pasted (roadmap 0224), bounded as the read tool bounds one (`ImageReader`): at most 2000 pixels on its long
/// side and small enough to send, re-encoded when it is not, or made a PNG or JPEG when no provider takes its kind.
public enum PastedImage {
    /// The picture as it will be sent, or why it cannot be.
    public static func bounded(_ bytes: [UInt8], limits: ImageLimits? = nil) -> Result<ImagePart, Refusal> {
        do {
            return .success(try ImageReader.read(bytes, allowance: ImageReader.Allowance(limits)).part)
        } catch {
            return .failure(Refusal(error))
        }
    }

    /// Why a pasted picture cannot be sent, in words.
    public struct Refusal: Error, Sendable, Equatable, CustomStringConvertible {
        public let description: String

        init(_ failure: ImageReader.Failure) {
            description =
                switch failure {
                    case .notAnImage: "it is not a picture ask can read (PNG, JPEG, GIF, WebP, HEIC, AVIF, TIFF or BMP)"
                    case .animated: "an animated PNG is not sent"
                    case .undecodable: "the picture could not be decoded"
                    case .cannotFit: "it could not be made small enough to send"
                }
        }
    }
}
