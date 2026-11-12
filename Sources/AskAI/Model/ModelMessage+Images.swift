extension ModelMessage {
    /// Whether any tool result in the message carries an image, or the person pasted one (roadmap 0224).
    public var holdsImages: Bool {
        blocks.contains { block in
            switch block {
                case .toolResult(_, _, _, let images): !images.isEmpty
                case .image: true
                default: false
            }
        }
    }
}
