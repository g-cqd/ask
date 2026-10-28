extension ModelMessage {
    /// Whether any tool result in the message carries an image.
    public var holdsImages: Bool {
        blocks.contains { if case .toolResult(_, _, _, let images) = $0 { !images.isEmpty } else { false } }
    }
}
