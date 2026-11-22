extension UISection {
    /// `self` with every key `section` sets replaced, each by its own declaration (``SettingDeclaration``, roadmap 0209).
    public func layered(with section: UISection) -> UISection {
        declaredLayered(with: section)
    }
}
