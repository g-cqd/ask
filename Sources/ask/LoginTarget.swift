internal import ArgumentParser

/// What `ask login` and `ask logout` can name.
enum LoginTarget: String, CaseIterable, ExpressibleByArgument {
    case claude
    case spettro
    case mistralVibe = "mistral-vibe"

    /// The name the credential file keeps this sign-in's key under, for the sign-ins that issue a key.
    var keyName: String? {
        switch self {
            case .claude: nil
            case .spettro: "spettro"
            case .mistralVibe: "mistral"
        }
    }
}
