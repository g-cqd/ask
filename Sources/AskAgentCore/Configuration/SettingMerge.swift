/// How a later layer's value of a setting combines with an earlier layer's (roadmap 0209), declared with the setting so that a layer
/// above the person's own file (MDM, roadmap 0130) can tell which of its values a lower layer may still make stricter.
enum SettingMerge: Sendable, Equatable {
    /// The later layer's value replaces the earlier one's, where the later layer sets one.
    case replaces
    /// A protective list: each layer adds its entries, and none takes one away (`environment.withhold`, `sandbox.hide`).
    case adds
    /// A scope: each layer can only narrow it (`sandbox.write`, `sandbox.read`, `sandbox.network`).
    case narrows
}
