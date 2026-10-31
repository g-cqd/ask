internal import Foundation
internal import Security

/// Whether a new build may replace the running one (owner, 2026-10-31; roadmaps 0153 and 0110): a build signed with a team's identity
/// moves only into a build that meets its own designated requirement, which names the signing certificate, not the code, so every
/// rebuild signed the same way passes and anything else placed at the executable's path does not. A running build with no team
/// identifier (ad hoc, as `swift build` makes) has no identity to compare, and the check says so instead of refusing.
public enum BuildSignature {
    public enum Verdict: Sendable, Equatable {
        /// The new build meets the running build's requirement.
        case sameSigner
        /// The running build has no stable identity, so nothing was compared.
        case unsignedRunning
        /// Why the new build may not be started, in a sentence.
        case refused(String)
    }

    /// The running process's designated requirement, as text, when it is signed with a team's identity; nil for an ad-hoc or platform
    /// signature, which names no team.
    public static func runningRequirement() -> String? {
        var code: SecCode?
        guard SecCodeCopySelf([], &code) == errSecSuccess, let code else { return nil }
        var staticCode: SecStaticCode?
        guard SecCodeCopyStaticCode(code, [], &staticCode) == errSecSuccess, let staticCode else { return nil }
        var information: CFDictionary?
        guard
            SecCodeCopySigningInformation(staticCode, SecCSFlags(rawValue: kSecCSSigningInformation), &information)
                == errSecSuccess,
            let values = information as? [String: Any], values[kSecCodeInfoTeamIdentifier as String] is String
        else { return nil }
        var requirement: SecRequirement?
        guard SecCodeCopyDesignatedRequirement(staticCode, [], &requirement) == errSecSuccess, let requirement else {
            return nil
        }
        var text: CFString?
        guard SecRequirementCopyString(requirement, [], &text) == errSecSuccess else { return nil }
        return text as String?
    }

    /// Checks the build at `path` against `requirement` (``runningRequirement()`` for a reload).
    /// - Parameters:
    ///   - path: the new build.
    ///   - requirement: the running build's designated requirement as text, or nil when it has none.
    /// - Returns: the verdict. Never throws: every way it can go wrong is a ``Verdict/refused(_:)``.
    public static func check(_ path: String, against requirement: String?) -> Verdict {
        guard let requirement else { return .unsignedRunning }
        var compiled: SecRequirement?
        guard SecRequirementCreateWithString(requirement as CFString, [], &compiled) == errSecSuccess, let compiled
        else {
            return .refused("the running build's signing requirement could not be read")
        }
        var staticCode: SecStaticCode?
        guard SecStaticCodeCreateWithPath(URL(filePath: path) as CFURL, [], &staticCode) == errSecSuccess,
            let staticCode
        else { return .refused("the new build could not be read") }
        let flags = SecCSFlags(rawValue: kSecCSCheckAllArchitectures | kSecCSStrictValidate)
        let status = SecStaticCodeCheckValidity(staticCode, flags, compiled)
        guard status == errSecSuccess else {
            return .refused(
                status == errSecCSUnsigned
                    ? "the new build is not signed"
                    : "the new build is not signed as the running build is (status \(status))")
        }
        return .sameSigner
    }
}
