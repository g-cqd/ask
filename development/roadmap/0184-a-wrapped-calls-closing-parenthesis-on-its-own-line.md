---
status: not-started
blocked-by: []
date: 2026-11-01
---

# 0184 — A wrapped call's closing parenthesis on its own line, across the family

Owner's report (2026-11-01): when a call's arguments wrap, its `)` goes on a line of its own, as `]`, `}` and a declaration's `)`
already do. swift-format offers only `"lineBreakBeforeEachArgument": true` for it, which also puts each argument of a wrapped call
on its own line. Done in arcleak, dolly, deadwood, fcheck, modeler and analyzerkit, which own their `.swift-format`.

## Still owed, in this order (the drift check compares each consumer with aemi at the revision its workflow pins)

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
