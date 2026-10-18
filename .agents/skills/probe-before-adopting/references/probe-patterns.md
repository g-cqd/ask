# Probe patterns that have worked here

Concrete shapes, each one from this repository's own history. Reuse the shape, not the conclusion.

## Bisect by elimination

**Claim:** "Upcoming-feature flag X breaks the test target."

**Probe:** remove one flag at a time from the full set, rebuilding each time. Then reduce the whole set
to the minimum.

**Result:** the build failed identically with `.swiftLanguageMode(.v6)` alone. The flags were never
involved.

**Why it matters:** a failure that survives the removal of the suspect is a *result*, not an
inconvenience. Stop blaming the flag and find the actual cause. Had the first result been accepted, a
false constraint would have entered the white paper and outlived the investigation.

## Change the configuration, not the code

**Claim:** "Nothing in the package needs anything above macOS 15, so the floor is a constraint."

**Probe:** build and run the full suite at floors 15, 26 and 27, changing nothing but the
`platforms:` line.

**Result:** 0 errors at all three, 6 tests passing at all three. The floor was a free choice.

**Why it matters:** the probe answered a different question than the one asked. The question was "is the
floor free?" and the probe was designed to detect a constraint — which it correctly did not find.

## Reproduce in a scratch copy

**Claim:** "`ask` builds against TerminalKit `main`."

**Probe:** copy the repository to `/tmp`, run `swift package update terminalkit`, build in release.

**Result:** 8 errors — `cannot find 'KittySequences' in scope`. `Package.resolved` had pinned a commit
from before the rename.

**Why it matters:** the live tree stayed untouched and clean throughout, and the failure reproduced
away from it. When a probe needs to mutate state, copy first.

## Break the guard you just wrote

**Claim:** "This documentation-layout test is load-bearing."

**Probe:** write a 300-line diary file. Run the suite. Remove it.

**Result:** the guard fired and named the offending file. It is load-bearing.

**Why it matters:** a test that has only ever passed has proven nothing. This is the cheapest probe in
the repository and the one most often skipped.

## Ask the emulator, then believe the emulator

**Claim:** "DECSTR (`CSI ! p`) resets DEC private modes."

**Probe:** a DECRQM round trip inside kitty, ghostty and wezterm, each launched as `-e /bin/sh -c` so no
shell configuration could contribute escape sequences. Write content and each tier in turn, then read
the terminal's own answer.

**Result:** refuted on all three. DECSTR reset no DEC private mode on any of them — which the oracle model
and the documentation had both asserted.

**Why it matters:** two implementations agreeing (the encoder and the oracle written from the spec) is
evidence. It is not proof. Only the emulator settles what a real user experiences.

## And when the harness itself is wrong

The first emulator harness reported PASS for all three tiers — because a double-quoted `\033` became a
real ESC that `send-text` swallowed, so every tier ran as a no-op.

Read the verdict, then read what the probe actually did. A harness that passes when it should fail is
worse than no harness, because it manufactures false confidence.

## Ask the platform, do not recall it

**Claim:** "`FoundationEssentials` is the module declaring `URL`."

**Probe:** add `import FoundationEssentials`, build, read the error.

**Result:** `unable to resolve module dependency`. The first guess was wrong and the build said so
plainly. The real cause was SE-0409 — `InternalImportsByDefault` makes a plain import grant *internal*
visibility — and the fix was an access level on the import.

For anything with an `@available` attribute or platform support, read the declaration. Memory of these
goes stale silently and there is no error when it is wrong.