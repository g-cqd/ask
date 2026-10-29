internal import Security
internal import Synchronization

/// Where keys and tokens are kept (`credentials`, roadmap 0110): the Keychain, or the credential file. `auto`, the default, is the
/// Keychain for a build signed with a stable identity and the file for an ad-hoc one, whose every rebuild the Keychain would ask about.
public enum CredentialStorage: String, Sendable, CaseIterable {
    case auto, keychain, file

    /// The values, as the configuration's error message lists them.
    public static let choices = allCases.map { "\"\($0.rawValue)\"" }.joined(separator: ", ")

    /// Whether this choice keeps secrets in the Keychain, for a build that is or is not signed with a stable identity.
    public func usesKeychain(stablySigned: Bool) -> Bool {
        switch self {
            case .auto: stablySigned
            case .keychain: true
            case .file: false
        }
    }

    /// The process's choice, set once the configuration is read; `auto` until then.
    private static let current = Mutex(CredentialStorage.auto)

    /// Makes `choice` the process's choice: credential files made from now on follow it.
    public static func choose(_ choice: CredentialStorage) { current.withLock { $0 = choice } }

    /// The process's choice.
    public static var chosen: CredentialStorage { current.withLock { $0 } }

    /// Whether the running binary is signed with an identity, not ad hoc: what makes its Keychain items readable across rebuilds.
    public static let runningBuildIsStablySigned: Bool = {
        var code: SecCode?
        guard SecCodeCopySelf([], &code) == errSecSuccess, let code else { return false }
        var staticCode: SecStaticCode?
        guard SecCodeCopyStaticCode(code, [], &staticCode) == errSecSuccess, let staticCode else { return false }
        var information: CFDictionary?
        guard
            SecCodeCopySigningInformation(staticCode, SecCSFlags(rawValue: kSecCSSigningInformation), &information)
                == errSecSuccess, let info = information as? [CFString: Any]
        else { return false }
        let flags = (info[kSecCodeInfoFlags] as? UInt32) ?? 0
        let adhoc = flags & UInt32(SecCodeSignatureFlags.adhoc.rawValue) != 0
        return !adhoc && info[kSecCodeInfoCertificates] != nil
    }()
}
