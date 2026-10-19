import Testing

@testable import AskAgentCore

/// Scopes and rules: the algebra that makes "layers only narrow" true, tested over every combination of a small
/// universe rather than a handful of examples.
@Suite("Scopes only ever narrow, and rules match as the kernel's own paths do")
struct PathScopeTests {
    private let paths = [
        "/w", "/w/a", "/w/a/b", "/w/ab", "/x", "/x/y", "/", "/W/A", "/w/a/../b"
    ]
    private var scopes: [PathScope] {
        [
            .anywhere, .roots([]), .roots(["/w"]), .roots(["/w/a"]), .roots(["/x"]), .roots(["/w", "/x"]),
            .roots(["/w/a", "/x/y"]), .roots(["/"])
        ]
    }

    @Test func `the intersection allows a path only if both scopes do, for every pair and path`() {
        for left in scopes {
            for right in scopes {
                let both = left.intersecting(right)
                for path in paths {
                    #expect(
                        both.contains(path) == (left.contains(path) && right.contains(path)),
                        "\(left) ∩ \(right) on \(path)")
                }
            }
        }
    }

    @Test func `intersecting is symmetric in what it allows, and never widens either side`() {
        for left in scopes {
            for right in scopes {
                for path in paths {
                    let one = left.intersecting(right).contains(path)
                    #expect(one == right.intersecting(left).contains(path))
                    if one { #expect(left.contains(path) && right.contains(path)) }
                }
            }
        }
    }

    @Test func `a root matches itself and what is under it, not a sibling that shares its prefix`() {
        let scope = PathScope.roots(["/w/a"])
        #expect(scope.contains("/w/a") && scope.contains("/w/a/b/c"))
        #expect(!scope.contains("/w/ab") && !scope.contains("/w"))
    }

    @Test func `rules match without regard to case, a literal only itself`() {
        let subpath = SandboxRule("/Users/g/.aws", .subpath)
        #expect(subpath.matches("/Users/g/.AWS") && subpath.matches("/users/G/.aws/credentials"))
        #expect(!subpath.matches("/Users/g/.awsome") && !subpath.matches("/Users/g"))
        let literal = SandboxRule("/Users/g/.ssh/id_rsa", .literal)
        #expect(literal.matches("/Users/g/.SSH/ID_RSA") && !literal.matches("/Users/g/.ssh/id_rsa.pub"))
        #expect(SandboxRule("/", .subpath).matches("/anything"))
    }
}
