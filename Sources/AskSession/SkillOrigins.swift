package import AskAgentCore

/// Where a run's skills may come from (roadmap 0130): every harness's folders and the organisation's (`skills` beside its
/// requirements); or, under its `policy.managedSkillsOnly`, the organisation's alone, and only while that folder belongs to root and
/// nobody else may write it, as its documents must.
package struct SkillOrigins: Sendable {
    /// Where skills are looked for.
    package let sources: [SkillSource]
    /// The selection the policy imposes in place of the person's `skills.sources`; nil when it imposes none.
    package let imposed: [String]?
    /// Why the organisation's folder offers nothing under the policy; nil otherwise.
    package let refusal: String?

    /// The id of the organisation's folder, as `skills.sources` and `--from` name it.
    package static let organisationID = "organisation"

    /// The origins `policy` leaves, with the organisation's folder at `folder`, trusted when it belongs to `owner` (root, unless a
    /// test names another).
    package static func of(
        _ policy: PolicySection,
        folder: String = ManagedFiles.systemDirectory + "/skills",
        owner: UInt32 = 0
    ) -> SkillOrigins {
        let organisation = SkillSource(id: organisationID, userRoots: [folder], projectRoots: [], bundledRoots: [])
        guard policy.managedSkillsOnly == true else {
            return SkillOrigins(sources: SkillSource.standard + [organisation], imposed: nil, refusal: nil)
        }
        do {
            try ManagedFiles.trust(folder, owner: owner)
        } catch {
            return SkillOrigins(
                sources: [],
                imposed: ["user"],
                refusal:
                    "Your organisation allows only its own skills (policy.managedSkillsOnly), and its folder cannot be used: \(error)"
            )
        }
        return SkillOrigins(sources: [organisation], imposed: ["user", organisationID], refusal: nil)
    }
}
