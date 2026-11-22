extension UISection {
    /// `self` with every key `section` sets replaced, each by its own declaration (``UISetting``, roadmap 0209).
    public func layered(with section: UISection) -> UISection {
        var merged = self
        for setting in UISetting.all { setting.layer(&merged, section) }
        return merged
    }
}
