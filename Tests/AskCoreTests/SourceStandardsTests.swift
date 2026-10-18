internal import Foundation
internal import Testing

@testable import AskCore

/// The standards, made mechanical.
///
/// Every rule here was followed by hand for months and drifted anyway — `NSLock` appeared in a test
/// helper in the same week it was written down. A rule nobody checks is a wish, which is the same
/// argument this project already makes about allocation ceilings.
///
/// Each rule is a **source scan**, not a compiler setting, because the compiler cannot express "this
/// type needs a written justification". So the scan is the guard, and the guard is itself probed by
/// introducing each violation and confirming it is caught.
@Suite("The source standards are enforced, not requested")
struct SourceStandardsTests {
    // MARK: - Banned outright

    /// Constructs with a modern replacement at this platform floor, which is macOS 26.
    ///
    /// The replacement is never a fallback here: the floor is high enough that `Mutex`, `Atomic`,
    /// `InlineArray`, `Span` and `RawSpan` all compile, so reaching for an older lock is not a
    /// compatibility decision.
    private static let banned: [(name: String, alternatives: String)] = [
        ("NSLock", "`Mutex` or `Atomic` from Synchronization"),
        ("os_unfair_lock", "`Mutex` from Synchronization"),
        ("pthread_mutex", "`Mutex` from Synchronization"),
        ("DispatchQueue", "`Task`, `TaskGroup`, `AsyncStream`, or a dedicated `Thread` for blocking I/O")
    ]

    /// `@unchecked Sendable` is deliberately absent from the list above. It is permitted with a written
    /// justification and is checked separately below, because a file descriptor cannot be made checked
    /// and banning it outright would push the code somewhere worse. Banning it here while allowing it
    /// there would be two rules contradicting each other in one file.
    @Test(arguments: SourceStandardsTests.banned)
    func `the banned construct is absent from the sources`(construct: (name: String, alternatives: String)) throws {
        let offenders = try SourceStandards.occurrences(of: construct.name, in: SourceStandards.sources)
        #expect(
            offenders.isEmpty,
            """
            `\(construct.name)` is banned. Use \(construct.alternatives).
            Found at: \(offenders.isEmpty ? "" : offenders.joined(separator: "\n  "))
            """
        )
    }

    // MARK: - Escapes that must be justified in writing

    /// `@unchecked Sendable` is not banned outright — a C pointer or a file descriptor cannot be made
    /// checked, and pretending otherwise produces a worse codebase. It is allowed **only** with the
    /// invariant written next to it, which is the rule this tests.
    @Test func `every unchecked Sendable carries a SAFETY comment`() throws {
        let offenders = try SourceStandards.uncheckedSendableWithoutSafetyComment()
        #expect(
            offenders.isEmpty,
            """
            Every `@unchecked Sendable` must state why the type is safe, on the same line or \
            the line above, beginning `SAFETY:`.
            Found: \(offenders.isEmpty ? "" : offenders.joined(separator: "\n  "))
            """
        )
    }

    // MARK: - Test determinism

    /// A test that yields, sleeps or polls is a test that can pass for the wrong reason.
    @Test func `no test yields or sleeps`() throws {
        let offenders = try SourceStandards.occurrences(
            of: "Task.yield", in: SourceStandards.tests)
        #expect(
            offenders.isEmpty,
            """
            `Task.yield` in a test makes the outcome depend on scheduling. Wait on an event instead — \
            Aemi's `AsyncEventProbe` under a `TestClock`, or a `CheckedContinuation` the code under \
            test resumes.
            Found: \(offenders.isEmpty ? "" : offenders.joined(separator: "\n  "))
            """
        )
    }

    @Test func `no test sleeps`() throws {
        let offenders = try SourceStandards.testSleeps()
        #expect(
            offenders.isEmpty,
            """
            `Task.sleep` in a test is a real-time deadline a loaded machine can trip. Use \
            `AsyncEventProbe.wait(forAtLeast:within:clock:)` under a `TestClock`, which ends on the \
            event rather than on elapsed time.
            Found: \(offenders.isEmpty ? "" : offenders.joined(separator: "\n  "))
            """
        )
    }
}
