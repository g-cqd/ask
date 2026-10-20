internal import Darwin

extension CredentialFileError: CustomStringConvertible {
    /// A sentence that names the file and says what to do. Never the file's contents.
    public var description: String {
        switch self {
            case .exposed(let path, let mode):
                "\(path) can be read by other users (mode \(String(mode, radix: 8))); run `chmod 600 \(path)`"
            case .damaged(let path):
                "\(path) is not valid credentials; repair it, or run `ask logout` to remove it and sign in again"
            case .io(let path, let code): "\(path): \(String(cString: strerror(code)).lowercased())"
            case .newerFormat(let path):
                "\(path) uses a newer connection format; update ask before reading or changing it"
            case .connectionChanged(let path): "the selected connection at \(path) changed; select it again explicitly"
            case .locked(let path): "another ask is saving credentials in \(path) and did not finish; try again"
        }
    }
}
