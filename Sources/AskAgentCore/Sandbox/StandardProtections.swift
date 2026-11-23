/// What the default policy protects besides ask's own directories (ADR-0035, security audit 2026-10-29), relative to the home unless
/// said otherwise. Every one is askable: a call may ask the person for it.
// @dl:accept -- lists of paths are data, like any other table of names
enum StandardProtections {
    /// Other tools' secret stores, kept unreadable: cloud and container credentials, package registries' tokens, browsers' profiles and
    /// cookies. Other agents' sign-ins name providers, so the composition root adds them (`otherSecrets`).
    static let secretDirectories = [
        // @dl:accept -- a table of names (programs or paths) reads like any list of strings; the entries are the content
        ".aws", ".gnupg", "Library/Keychains", ".config/gh", ".kube", ".config/gcloud", ".azure", "Library/Cookies",
        // @dl:accept -- a table of names (programs or paths) reads like any list of strings; the entries are the content
        "Library/Application Support/Google/Chrome",
        "Library/Application Support/BraveSoftware", "Library/Application Support/Microsoft Edge",
        "Library/Application Support/Arc", "Library/Application Support/Firefox",
        // Security audit 2026-11-22 (CRIT-01, MED-08): Safari's, password managers' and pass's stores, and mail and messages.
        "Library/Safari", "Library/Containers/com.apple.Safari", "Library/Group Containers/2BUA8C4S2C.com.1password",
        "Library/Application Support/1Password", "Library/Application Support/Bitwarden", ".password-store",
        ".config/op",
        "Library/Messages", "Library/Mail"
    ]

    /// Places named by how they start, for apps whose data takes their identifier with several endings (`.dev`, `.binarycookies`):
    /// Sunset's vault, cookies, site data and caches, and Safari's per-app storage (security audit 2026-11-22, CRIT-01).
    static let secretPrefixes = [
        "Library/Application Support/Sunset", "Library/HTTPStorages/studio.aemi.sunset",
        "Library/HTTPStorages/sunset-app",
        "Library/WebKit/studio.aemi.sunset", "Library/WebKit/sunset-app", "Library/Caches/studio.aemi.sunset",
        // @dl:accept -- a table of names (programs or paths) reads like any list of strings; the entries are the content
        "Library/HTTPStorages/com.apple.Safari", "Library/WebKit/com.apple.Safari", "Library/Caches/com.apple.Safari"
    ]

    /// Other apps' files in the user's temporary folder, by how their names start (security audit 2026-11-22, MED-07): Sunset's
    /// extension downloads, notification icons, imports and content-blocking lists. The folder itself stays open: xcrun and every
    /// Foundation-based tool write there whatever `TMPDIR` says (probed, diary 2026-11-22-05).
    // @dl:accept -- a table of names (programs or paths) reads like any list of strings; the entries are the content
    static let temporaryPrefixes = ["sunset-", "SunsetBlocking"]

    /// Single secret files: netrc, registries' tokens, git's stored credentials, Docker's, and ssh private keys (not
    /// `~/.ssh/config` or `known_hosts`, which `git` over ssh reads).
    static let secretFiles =
        // @dl:accept -- a table of names (programs or paths) reads like any list of strings; the entries are the content
        [
            ".netrc", ".npmrc", ".pypirc", ".git-credentials", ".config/git/credentials", ".docker/config.json",
            // Security audit 2026-11-22 (MED-08). Not `.m2/settings.xml` or `gradle.properties`, which builds read.
            ".pgpass", ".my.cnf", ".vault-token", ".terraform.d/credentials.tfrc.json", ".cargo/credentials.toml",
            ".cargo/credentials", ".gem/credentials", ".composer/auth.json", ".config/composer/auth.json",
            ".zsh_history",
            ".bash_history", ".local/share/fish/fish_history"
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
