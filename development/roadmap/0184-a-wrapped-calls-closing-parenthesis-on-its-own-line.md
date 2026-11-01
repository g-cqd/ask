---
status: done
blocked-by: []
date: 2026-11-01
---

# 0184 — A wrapped call's closing parenthesis on its own line, across the family

Owner's report (2026-11-01): when a call's arguments wrap, its `)` goes on a line of its own, as `]`, `}` and a declaration's `)`
already do. swift-format offers only `"lineBreakBeforeEachArgument": true` for it, which also puts each argument of a wrapped call
on its own line. Done in arcleak, dolly, deadwood, fcheck, modeler and analyzerkit, which own their `.swift-format`.

## The plan, as first written (the outcome follows), in this order (the drift check compares each consumer with aemi at the revision its workflow pins)

1. aemi: the setting in the canonical `.swift-format`, aemi reformatted (189 files), and `AemiKernels.swift`'s type body brought
   under the limit; pushed.
2. Each consumer in one commit: its `swift-quality.yml` pin moved to that aemi revision where it has one, `scripts/sync-config.sh`
   run (Atelier's three nested configs too), reformatted, and the files now over a limit split. AemiJSON (`SchemableMacro.swift`),
   AemiProtobuf (`SchemaComparator.swift`), TerminalKit (`Rope.swift`), AemiMarkdown and AemiRegex (none), ask (20 violations in 16
   files), Atelier (22 in 18).
3. Before syncing: AemiProtobuf, Atelier, TerminalKit and ask have a `.swiftlint.yml` that already differs from aemi's; review those
   differences, since the sync overwrites them.
4. Check how AemiMarkdown, AemiProtobuf, TerminalKit and ask get the config in CI, where no pinned `swift-quality.yml` call was found.

Not covered: AemiSwift, AemiUI and AemiUtilities have no swift-format config; swift-search and SwiftStaticAnalysis own theirs.

## Done (2026-11-01)

| Repository | Commit | Files | Split to stay within the limits |
|---|---|---|---|
| aemi | `0ef4279` | 189 | `AemiKernels`' UTF-8 scans |
| AemiRegex | `66992fa` | 51 | none |
| AemiMarkdown | `8203c3c` | 28 | none |
| AemiJSON | `b1412a5` | 93 | `SchemableMacro`'s scalar fragments |
| AemiProtobuf | `fcccfc3` | 153 | five files past its own 250-line rule (`SourceStructureTests`) |
| TerminalKit | `c1d021c` | 93 | `RopeNode`'s edits |
| ask | `47eef6b` | 749 | 12 files, 8 types, 12 functions |
| Atelier | `abd7b1c` | 725 | 13 types and files, 10 functions |

- Formatted with the layout settings alone (a copy of the config with every rule off), so only line breaks and indentation
  changed. A full `swift-format format` also applies the rules, which in aemi rewrote access levels and turned a `fileprivate`
  test class `private`, breaking the Loggable macro test; files that already broke a rule were formatted with the rules only
  where the commit check asked.
- Nothing is exempted: each split moves a section into an extension file of its type, or a helper, or joins a call that fits on
  one line. Members the moved code reads go from `private` to `internal` (or `package` where the module uses it).
- dolly's fingerprints hash the line, so AemiJSON's and AemiProtobuf's baselines were rewritten after checking the findings by
  rule, file and message were the same (no new warning). In ask, one argument per line made 13 clones visible that its
  line-anchored `@dl:accept` directives had covered; each directive now sits on the clone's new first line, with its reason
  unchanged.
- The workflow pins of AemiRegex, AemiJSON and Atelier name aemi `0ef4279`. The `.swiftlint.yml` files that differ from aemi's
  were left as they are, not synced.
- Package pins still name aemi `6d8e862`; the change is formatting only, and the next `Scripts/update-pins.py` run moves them.
- Not covered, as the report found: AemiSDR (its own config), swift-search and SwiftStaticAnalysis (their own), AemiSwift,
  AemiUI and AemiUtilities (no swift-format config).
