extension Configuration.Setting where Value: LayeredSection {
    /// This setting with `section`'s keys over it, from `source`; unchanged when the layer does not have the section.
    func layered(_ section: Value?, from source: Configuration.Source) -> Self {
        guard let section else { return self }
        return Self(value: value.layered(with: section), source: source)
    }
}
