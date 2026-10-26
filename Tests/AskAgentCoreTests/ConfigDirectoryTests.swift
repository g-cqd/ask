import Testing

@testable import AskAgentCore

/// Where ask keeps its configuration (roadmap 0028): `$XDG_CONFIG_HOME/ask` when that is an absolute path, else `~/.config/ask`. A
/// relative `XDG_CONFIG_HOME` is ignored, as the XDG specification says, because it would move with the working directory.
@Suite("ask's configuration directory follows XDG, and only an absolute path counts")
struct ConfigDirectoryTests {
    @Test func `an absolute XDG_CONFIG_HOME is the base`() {
        #expect(ConfigDirectory.path(environment: ["XDG_CONFIG_HOME": "/etc/xdg"], home: "/Users/x") == "/etc/xdg/ask")
    }

    @Test func `no XDG_CONFIG_HOME uses the home's .config`() {
        #expect(ConfigDirectory.path(environment: [:], home: "/Users/x") == "/Users/x/.config/ask")
    }

    @Test func `a relative XDG_CONFIG_HOME is ignored`() {
        #expect(
            ConfigDirectory.path(environment: ["XDG_CONFIG_HOME": "relative/dir"], home: "/Users/x")
                == "/Users/x/.config/ask")
    }

    @Test func `an empty XDG_CONFIG_HOME is ignored`() {
        #expect(ConfigDirectory.path(environment: ["XDG_CONFIG_HOME": ""], home: "/Users/x") == "/Users/x/.config/ask")
    }
}
