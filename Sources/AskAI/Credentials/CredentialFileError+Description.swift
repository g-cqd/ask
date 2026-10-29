internal import Darwin

extension CredentialFileError: CustomStringConvertible {
    /// A sentence that names the file and says what to do. Never the file's contents.
    public var description: String {
        switch self {
            case .exposed(let path, let mode):
                "\(path) can be read by other users (mode \(String(mode, radix: 8))); run `chmod 600 \(path)`"
            case .damaged(let path):
                "\(path) is not valid credentials; repair it, or run `ask logout` to remove it and sign in again"
            // @dl:accept -- diagnostic sentences per case; the thinking errors' descriptions are independent data
            case .io(let path, let code): "\(path): \(String(cString: strerror(code)).lowercased())"
            case .newerFormat(let path):
                "\(path) uses a newer connection format; update ask before reading or changing it"
            case .connectionChanged(let path): "the selected connection at \(path) changed; select it again explicitly"
            case .locked(let path): "another ask is saving credentials in \(path) and did not finish; try again"
            case .secretMissing(let path, let record):
                "\(path) keeps the secrets of \(record) in the Keychain, and the Keychain has none; sign in again for it"
            case .secretStore(let path, let status):
                "the Keychain refused the secrets of \(path) (status \(status)); unlock it, or set credentials to \"file\""
        }
    }
}
