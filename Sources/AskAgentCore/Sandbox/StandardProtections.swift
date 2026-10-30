/// What the default policy protects besides ask's own directories (ADR-0035, security audit 2026-10-29), relative to the home unless
/// said otherwise. Every one is askable: a call may ask the person for it.
// @dl:accept -- lists of paths are data, like any other table of names
enum StandardProtections {
    /// Other tools' secret stores, kept unreadable: cloud and container credentials, package registries' tokens, browsers' profiles and
    /// cookies. Other agents' sign-ins name providers, so the composition root adds them (`otherSecrets`).
    static let secretDirectories = [
        ".aws", ".gnupg", "Library/Keychains", ".config/gh", ".kube", ".config/gcloud", ".azure", "Library/Cookies",
        "Library/Application Support/Google/Chrome",
        "Library/Application Support/BraveSoftware", "Library/Application Support/Microsoft Edge",
        "Library/Application Support/Arc", "Library/Application Support/Firefox"
    ]

    /// Single secret files: netrc, registries' tokens, git's stored credentials, Docker's, and ssh private keys (not
    /// `~/.ssh/config` or `known_hosts`, which `git` over ssh reads).
    static let secretFiles =
        [
            ".netrc", ".npmrc", ".pypirc", ".git-credentials", ".config/git/credentials", ".docker/config.json"
        ]
        + ["id_rsa", "id_dsa", "id_ecdsa", "id_ed25519", "id_ecdsa_sk", "id_ed25519_sk"].map { ".ssh/" + $0 }

    /// Places whose contents run later, outside ask's sandbox, kept unwritable: launch agents, login items, fish's and git's
    /// configuration directories.
    static let runningDirectories = [
        "Library/LaunchAgents", "Library/Application Support/com.apple.backgroundtaskmanagementagent", ".config/fish",
        ".config/git"
    ]

    /// Single files that run later: shell startup files, git's configuration (its hooks and aliases run programs), and what ssh runs
    /// or lets in. `~/.ssh/known_hosts` stays writable: ssh records a new host there.
    static let runningFiles = [
        // @dl:accept -- a list of file names is data, like any other table of names
        ".zshrc", ".zshenv", ".zprofile", ".zlogin", ".zlogout", ".bashrc", ".bash_profile", ".bash_login",
        ".bash_logout",
        ".profile", ".gitconfig", ".ssh/authorized_keys", ".ssh/authorized_keys2", ".ssh/config", ".ssh/rc",
        ".ssh/environment"
    ]

    /// System-wide places that run later, from the root.
    static let systemRunningDirectories = ["Library/LaunchAgents", "Library/LaunchDaemons"]
}
