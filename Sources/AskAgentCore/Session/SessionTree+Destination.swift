extension SessionTree {
    /// The latest recorded destination on the active branch, even when earlier messages have been compacted.
    public var destination: SessionDestination? {
        guard let entry = nearest(where: { $0 == .destination }),
            case .destination(let destination) = entry.payload
        else { return nil }
        return destination
    }
}
