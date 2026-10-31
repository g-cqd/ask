extension ThinkingControl {
    /// What the provider's default level sends for a Claude model described by `descriptor`: on a model that cannot stop thinking (its
    /// catalog offers adaptive thinking and no way to disable it), its default is adaptive thinking, so that is sent, with the thinking's
    /// summary asked for: models from Opus 4.7 on otherwise stream it empty. Anywhere else, nothing, so the provider's default stands.
    public static func providerDefault(descriptor: CatalogModel?) -> ThinkingControl? {
        guard let modes = descriptor?.thinkingModes, modes.contains(.adaptive), !modes.contains(.disabled) else {
            return nil
        }
        return .adaptive
    }
}
