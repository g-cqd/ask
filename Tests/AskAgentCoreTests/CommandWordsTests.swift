import Testing

@testable import AskAgentCore

/// What a session grant for a command names (roadmap 0134): the program and its subcommand (`git status`), and the program alone (`git`),
/// for every command a line runs. A line whose commands cannot all be known (a substitution) is never covered by a grant.
@Suite("The words a command's grant names")
struct CommandWordsTests {
    @Test func `a program and its subcommand, without options, paths or variables`() {
        let words = CommandWords("git status -s")
        #expect(words.phrases == ["git status"] && words.programs == ["git"] && words.coverable)
        // Leading assignments still name the program for display, but are never coverable by a session grant (N-A1).
        let assigned = CommandWords("FOO=1 /usr/bin/swift build -c release")
        #expect(assigned.phrases == ["swift build"])
        #expect(assigned.programs == ["swift"])
        #expect(!assigned.coverable)
        #expect(CommandWords("rm -rf build").phrases == ["rm"], "an option is not a subcommand")
        #expect(CommandWords("cat notes.txt").phrases == ["cat"], "a file is not a subcommand")
    }

    @Test func `every command of a line is named`() {
        let words = CommandWords("git add . && git commit -m x; swift test | tail -3")
        #expect(words.phrases == ["git add", "git commit", "swift test", "tail"])
        #expect(words.programs == ["git", "swift", "tail"])
        #expect(words.coverable)
    }

    @Test func `a substitution or a backquote makes the line uncoverable`() {
        #expect(!CommandWords("echo $(rm -rf x)").coverable)
        #expect(!CommandWords("echo `id`").coverable)
        #expect(!CommandWords("").coverable)
    }

    /// Security audit 2026-11-22 (CRIT-04) & security review 2026-11-25 (N-A1): each of these was covered by a grant
    /// for `git status`, `git`, `env`, `xargs`, `find`, `echo`, `rg`, `tar`, `zip`, `awk`, or `sed`.
    @Test func `a line that runs a command its words do not name is never covered`() {
        let grants = CallGrants(
            phrases: ["git status", "rg pattern", "tar xf"],
            programs: "git env xargs find echo rg tar zip awk perl sed make npm".split(separator: " ").map(String.init),
            files: [],
            tools: []
        )
        let blocked = """
            git status > >(sh -c 'evil')
            git status 2>>(sh)
            echo hi | tee >(sh)
            git -c core.pager='sh -c evil' log
            git --config-env=core.pager=X status
            git --exec-path=/tmp/x status
            env sh -c evil
            xargs sh -c evil
            find . -exec sh -c evil \\;
            find . -okdir rm {} +
            echo x && bash -c evil
            eval echo
            PATH=. git status
            GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=core.fsmonitor GIT_CONFIG_VALUE_0='id' git status
            BASH_ENV=/tmp/pwn.sh git status
            x=$'\\x24(id)'; echo ${x@P}
            echo $HOME
            echo "$HOME"
            echo done > /tmp/pwn
            git status > /tmp/out
            rg --pre sh pattern
            tar --to-command=sh -xf a.tar
            tar --use-compress-program=sh -xf a.tar
            zip -TT sh a.zip b
            awk 'BEGIN { system("id") }'
            sed -i '' 's/a/b/' file
            make all
            npm run build
            """
            .split(separator: "\n")
            .map(String.init)
        for line in blocked {
            #expect(!grants.covers(.command(CommandWords(line))), "\(line)")
        }
        for line in [
            "git status -s", "git log -c --stat", "find . -name '*.swift'", "rg 'foo$bar' Sources", "echo 'literal $x'"
        ] {
            #expect(grants.covers(.command(CommandWords(line))), "still covered: \(line)")
        }
    }

    @Test func `execution-hijack environment variables are withheld by default`() {
        let policy = CommandEnvironment(credentials: [], credentialPrefixes: [], configured: EnvironmentSection())
        let names =
            "BASH_ENV ENV GIT_CONFIG_COUNT GIT_CONFIG_KEY_0 GIT_CONFIG_VALUE_0 GIT_SSH_COMMAND GIT_PAGER GIT_EXTERNAL_DIFF LESSOPEN DYLD_INSERT_LIBRARIES"
            .split(separator: " ")
            .map(String.init)
        for name in names {
            #expect(policy.withholds(name), "expected withheld: \(name)")
        }
        #expect(!policy.withholds("PATH"))
        #expect(!policy.withholds("HOME"))
    }
}
