internal import Testing

@testable import AskMCP

/// What a server's process is given to run in (ADR-0096). ask's own environment holds its API keys and its users' tokens; a server is
/// third-party code, so it gets what a program needs to run and what the configuration names, and nothing else, as the reference SDKs do.
@Suite("A server's process gets a minimal environment plus what was configured")
struct StdioLaunchTests {
    private let ask = [
        "PATH": "/usr/bin:/bin", "HOME": "/Users/x", "USER": "x", "LOGNAME": "x", "SHELL": "/bin/zsh", "TERM": "xterm",
        "TMPDIR": "/tmp/x/", "LANG": "en_US.UTF-8", "LC_ALL": "C", "LC_CTYPE": "UTF-8",
        "ANTHROPIC_API_KEY": "sk-secret", "OPENAI_API_KEY": "sk-other", "GITHUB_TOKEN": "ghp_x",
        "AWS_SECRET_ACCESS_KEY": "s",
        "SSH_AUTH_SOCK": "/tmp/agent", "ASK_HOME": "/x"
    ]

    @Test func `what a program needs to run is passed on`() {
        let environment = StdioLaunch.childEnvironment(inheriting: ask, adding: [:])
        #expect(
            Set(environment.keys) == [
                "PATH", "HOME", "USER", "LOGNAME", "SHELL", "TERM", "TMPDIR", "LANG", "LC_ALL", "LC_CTYPE"
            ])
        #expect(environment["PATH"] == "/usr/bin:/bin")
    }

    @Test func `keys, tokens and sockets are not passed on, however they are named`() {
        let environment = StdioLaunch.childEnvironment(inheriting: ask, adding: [:])
        for name in [
            "ANTHROPIC_API_KEY", "OPENAI_API_KEY", "GITHUB_TOKEN", "AWS_SECRET_ACCESS_KEY", "SSH_AUTH_SOCK", "ASK_HOME"
        ] {
            #expect(environment[name] == nil, "\(name)")
        }
    }

    @Test func `what the configuration names is added, and wins over what was inherited`() {
        let environment = StdioLaunch.childEnvironment(
            inheriting: ask, adding: ["GITHUB_TOKEN": "ghp_chosen", "HOME": "/elsewhere"])
        #expect(environment["GITHUB_TOKEN"] == "ghp_chosen" && environment["HOME"] == "/elsewhere")
    }

    @Test func `an environment with nothing in it gives a child with nothing but what was added`() {
        #expect(StdioLaunch.childEnvironment(inheriting: [:], adding: ["A": "1"]) == ["A": "1"])
    }
}
