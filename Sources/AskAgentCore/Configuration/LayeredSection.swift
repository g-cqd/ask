/// A configuration section whose layers combine key by key: a layer replaces the keys it sets and leaves the others.
protocol LayeredSection: Sendable, Equatable {
    /// `self` with every key `section` sets replaced.
    func layered(with section: Self) -> Self
}
