# What the installed skills do not say

From the 2026-10-19 quality audit. Read from each skill's `SKILL.md`; the `references/` folders were not
read exhaustively, so "does not say" means "not in the body that gets loaded". Each item has a probe or an
observation behind it in `docs/diary/2026-10-19-04.md`.

| Skill | Gap | Seen as |
|---|---|---|
| `swift` | Says a class or module should have one responsibility, but not that a file should be named for its one type, nor how to gate it | 30 of 70 files hid several types |
| `swift` | §6 prescribes a debug build while developing and one release build per task. This project builds release only (ADR-0002). `project-conventions` outranks it, but nothing says to check | pre-push ran a debug build |
| `swift` | Silent on `InternalImportsByDefault`: with warnings as errors an unused `public import` is a build error, and splitting a file creates them | a build error per copied import after the split |
| `swift` | Silent on `fileprivate` hiding coupling between types in one file | 3 members widened by the split |
| `swift` | Not covered: `Regex` is not `Sendable` in Swift 6.4, so a `static let` fails | build error |
| `testing` | Says to run mutation testing for tests that cannot fail, but not the cheap version for a *guard*: break the rule on purpose and watch the guard fire | every new gate was broken once; one test had never been red |
| `testing` | No pattern for structural tests that scan source text, nor for keeping test files themselves in shape (one suite per file, doubles nested) | test files held 5 types |
| `code-review` | Flags types with too many concerns, but has no mechanical backstop, and nothing on judging whether an abstraction takes a second implementation | provider seam |
| `engineering-practices` | Hand-back assumes you own the working tree. Nothing on a second writer with a staged index in the same checkout | would have been swept into their commit |
| `engineering-practices` | "Verification" has no step for checking that the hooks and CI actually fire | hooks were stale and one was exploitable |
| `project-conventions` | Says linter configs are enforced rules; does not say to probe that they are, nor to look for what they exclude | `Tests/` excluded; hooks ran debug tests |
| `performance-engineering` / tooling | SwiftPM 6.4's default build system writes no index store and ignores `-index-store-path`; tools that need one (Periphery) need `--build-system native` | Periphery found no store |
| any | `cp -Rc` of a repository with its `.build` yields a copy that cannot build (absolute paths). Clone, then delete `.build` | C target failed |
| any | A generated git hook is a copy made at install time. A fix upstream does not reach existing repositories until `repair` runs | 158 stale generated hooks on this machine (dry-run) |
| `agora` | Not consulted during the audit, so whether it would have helped with the second writer was not checked | worked around with a branch |

## Questions the skills suggest and the project has not answered

Provider generality and harness-feature extension points. Roadmap 0026 and 0027 hold them, as claims with
probes that can fail them. Until then they are open questions, never facts.
