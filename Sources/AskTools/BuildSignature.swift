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

    /// The running build's signature, as far as it can be known.
    public enum Running: Sendable, Equatable {
        /// Signed with a team's identity; its designated requirement as text.
        case signed(String)
        /// Ad hoc or platform signed: no team, so nothing to compare.
        case unsigned
        /// The executable's file no longer matches the running code (a new build replaced it), so its signature cannot be read.
        case unreadable
    }

    /// Reads the running build's signature from its executable's file, then checks that the running code still matches that file.
    /// The file is what a new build replaces: read after that, it would give the new build's signature, or none. A mismatch is
    /// ``Running/unreadable``, never ``Running/unsigned``. ``LaunchSignature`` reads it once at launch.
    public static func readRunning() -> Running {
        var code: SecCode?
        guard SecCodeCopySelf([], &code) == errSecSuccess, let code else { return .unreadable }
        var staticCode: SecStaticCode?
        guard SecCodeCopyStaticCode(code, [], &staticCode) == errSecSuccess, let staticCode else { return .unreadable }
        let read = requirement(of: staticCode)
        // After the read: a file swapped before or during it fails here.
        guard SecCodeCheckValidity(code, [], nil) == errSecSuccess else { return .unreadable }
        return read
    }

    private static func requirement(of staticCode: SecStaticCode) -> Running {
        var information: CFDictionary?
        guard
            SecCodeCopySigningInformation(staticCode, SecCSFlags(rawValue: kSecCSSigningInformation), &information)
                == errSecSuccess,
            let values = information as? [String: Any]
        else { return .unreadable }
        guard values[kSecCodeInfoTeamIdentifier as String] is String else { return .unsigned }
        var requirement: SecRequirement?
        var text: CFString?
        guard SecCodeCopyDesignatedRequirement(staticCode, [], &requirement) == errSecSuccess, let requirement,
            SecRequirementCopyString(requirement, [], &text) == errSecSuccess, let text
        else { return .unreadable }
        return .signed(text as String)
    }

    /// Checks the build at `path` against the running build's signature.
    /// - Parameters:
    ///   - path: the new build.
    ///   - running: the running build's signature (``LaunchSignature/running`` for a reload).
    /// - Returns: the verdict. Never throws: every way it can go wrong is a ``Verdict/refused(_:)``.
    public static func check(_ path: String, against running: Running) -> Verdict {
        let requirement: String
        switch running {
            case .signed(let text): requirement = text
            case .unsigned: return .unsignedRunning
            case .unreadable:
                return .refused(
                    "the running build's file has changed since it started, so its signature cannot be compared")
        }
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
