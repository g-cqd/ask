/// What a `modelScopes` rule makes of the provider a run would use (roadmap 0094, ADR-0137).
public enum ModelScopeVerdict: Sendable, Equatable {
    case allowed
    /// You named it (`--provider`, `--model`, `/model`): refused with this text, since a rule is a policy that no flag overrides.
    case refused(String)
    /// A file, a resumed session or ask's own pick chose it: the rule's first provider serves instead, and the text says so.
    case replaced(by: String, String)
}
