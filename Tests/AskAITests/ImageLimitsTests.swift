import Foundation
import Testing

@testable import AskAI

/// What a provider says it accepts of images bounds what a request holds (roadmap 0084).
@Suite("A request holds only the images, of the types and in the number, the provider allows")
struct ImageLimitsTests {
    private func result(_ id: String, _ types: [String]) -> ModelMessage {
        ModelMessage(
            role: .user,
            blocks: [
                .toolResult(
                    id: id, content: id, isError: false, images: types.map { ImagePart(mediaType: $0, data: [1]) })
            ])
    }

    private func counts(_ messages: [ModelMessage]) -> [Int] {
        messages.map {
            guard case .toolResult(_, _, _, let images) = $0.blocks[0] else { return -1 }
            return images.count
        }
    }

    private func text(_ message: ModelMessage) -> String {
        guard case .toolResult(_, let content, _, _) = message.blocks[0] else { return "" }
        return content
    }

    @Test func `a media type the provider does not list is replaced by a line saying so`() {
        let limits = ImageLimits(mediaTypes: ["image/png"])
        let out = ImagePart.filtering([result("a", ["image/png", "image/gif"])], accepts: true, limits: limits)
        #expect(counts(out) == [1])
        #expect(text(out[0]).contains("does not take image/gif"))
    }

    @Test func `over the allowance the oldest images go, down to half of it, and the newest stay`() {
        let messages = (0 ..< 5).map { result("r\($0)", ["image/png"]) }
        let out = ImagePart.filtering(messages, accepts: true, limits: ImageLimits(maximumImages: 4))
        // 5 > 4, so drop down to 2: the three oldest go.
        #expect(counts(out) == [0, 0, 0, 1, 1])
        #expect(text(out[0]).contains("an older image, removed to stay within the 4"))
        #expect(
            counts(ImagePart.filtering(Array(messages.prefix(4)), accepts: true, limits: ImageLimits(maximumImages: 4)))
                == [1, 1, 1, 1])
    }

    @Test func `a provider that says nothing is held to the default and an allowance of one keeps one`() {
        let many = (0 ..< (ImagePart.defaultMaximumImages + 1)).map { result("r\($0)", ["image/png"]) }
        #expect(counts(ImagePart.filtering(many, accepts: true)).reduce(0, +) == ImagePart.defaultMaximumImages / 2)
        let two = [result("a", ["image/png"]), result("b", ["image/png"])]
        #expect(counts(ImagePart.filtering(two, accepts: true, limits: ImageLimits(maximumImages: 1))) == [0, 1])
    }

    @Test func `limits describe themselves for a table`() {
        let all = ImageLimits(maximumImages: 5, maximumBytes: 3_000_000, mediaTypes: ["image/jpeg", "application/pdf"])
        #expect(all.summary == "5 images, 3 MB, jpeg pdf")
        #expect(ImageLimits().summary == "unknown")
    }
}
