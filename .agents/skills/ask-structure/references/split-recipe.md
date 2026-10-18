# Splitting a multi-type file

Used to split 27 files on 2026-10-19 with a throwaway script; the recipe is kept, the script is not, because
it was written for one pass and the compiler does the real checking.

## Steps

1. List each file's top-level declarations with their line extents, and their access level. A type's extent
   is its declaration line to the first line that is exactly `}` in column zero, with the contiguous
   `///`, `//` and `@attribute` lines above it. Everything not inside a declaration (free functions,
   constants, the file's header comment) stays with the file.
2. Decide per extra type: **own file**, or **nest** into the one type that uses it. Nest a `private` helper
   used by a single type. Give a type its own file when it is `public`/`internal`, used from another file, or
   a concept worth seeing in the listing. A test double used by several suites is its own file.
3. Cut the extents out of the original and write each to `<TypeName>.swift`. Extensions of a moved type move
   with it. A `private` type that becomes a file of its own loses `private`.
4. Give each new file only the imports it uses. A copied `public import X` that no public declaration needs
   is a compile error here (`InternalImportsByDefault`, warnings as errors): downgrade it to `internal
   import`, or drop it. Periphery (below) finds plain imports that are unused.
5. **Build once and read the whole error list.** Expect `fileprivate` members that now cross a file boundary
   (`'x' is inaccessible due to 'fileprivate' protection level`). Making them `internal` is correct and is
   the coupling the split exposed. Do not rebuild after each one.
6. Check nothing was lost: every non-blank line of the original (ignoring imports, whitespace and access
   modifiers) must exist in the new tree. swift-format will rewrap nested code, so compare tokens, not lines.
7. Move files into concern directories with `git mv`, and run `Scripts/quality.sh`.

## Traps seen

- A script that deletes the original when nothing is "primary" also deletes the free functions in it.
  `AskTUI.swift` lost `runAskTUI` this way, and only a lossless check caught it.
- A file header comment that describes the whole file belongs on the declaration that does the work, not on
  whichever new file came first.
- `static let` of a `Regex` does not compile in Swift 6 mode (`Regex` is not `Sendable`).
- Periphery needs an index store; SwiftPM 6.4's default build system writes none. Build with
  `swift build --build-system native --build-tests --scratch-path /tmp/x`, then
  `periphery scan --skip-build --index-store-path /tmp/x/debug/index/store`. Read only "Unused imported
  module" and "Assign-only"; "Redundant public accessibility" is meaningless under `@testable`, and the
  output includes dependency checkouts.
