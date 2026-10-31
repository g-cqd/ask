/// A provider named for this run that a `modelScopes` rule does not allow (roadmap 0094), said with the rule and what it allows.
struct ModelScopeRefusal: Error, CustomStringConvertible {
    let description: String
}
