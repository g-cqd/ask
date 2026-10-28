import AskAI
import Testing

@testable import AskAgentCore

/// The context an image adds is estimated by a fixed cost, never by its base64 length (roadmap 0084).
@Suite("An image counts as a fixed cost in the context, not as its bytes")
struct CompactionImageCostTests {
    private func result(images: [ImagePart]) -> SessionPayload {
        .toolResult(callID: "c", content: "abc", isError: false, images: images)
    }

    @Test func `each image adds the same cost whatever its size`() {
        let small = ImagePart(mediaType: "image/png", data: [1])
        let large = ImagePart(mediaType: "image/png", data: Array(repeating: 7, count: 200_000))
        #expect(Compaction.size(result(images: [])) == 3)
        #expect(Compaction.size(result(images: [small])) == 3 + Compaction.imageBytes)
        #expect(Compaction.size(result(images: [large, small])) == 3 + 2 * Compaction.imageBytes)
    }
}
