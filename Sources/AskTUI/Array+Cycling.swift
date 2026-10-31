extension Array where Element: Equatable {
    /// The element `step` places after `current`, wrapping at either end; from the first element when `current` is not here, nil when
    /// the array is empty. What a picker's arrows and a section's Tab both do.
    func cycled(from current: Element, by step: Int) -> Element? {
        guard !isEmpty else { return nil }
        let index = firstIndex(of: current) ?? 0
        return self[((index + step) % count + count) % count]
    }
}
