---
status: not-started
blocked-by: []
date: 2026-11-01
---

# 0189 — The gate and the tooling in Swift, in a deterministic Swift environment

Owner wish (2026-11-01): format once, at the start; convert the bash and Python scripts to Swift package plugin commands, relying on
a deterministic Swift environment.

Owner answers (2026-11-01):

- Scope: the gate (`quality.sh`, `analyzers.sh`, `dependency-audit.sh`, the `check-*` and `test-*` guards) and the tooling
  (`update-pins`, `land`, `sign`, `mutate-changed`, `record_numbers`, `generate-order-file`, `measure-*`). The probes come later, as an
  item of their own, with a VT parser of ask's own in place of pyte; `development/research` and `prototypes` are records, not ported.
- A separate `Tools/` package holds the executables and their dependencies, so ask's own graph and `Package.resolved` stay as they are.
- Third-party tools checksummed: SwiftLint as an artifactbundle binary target, swift-format from the toolchain `.swift-version` pins,
  deadwood, dolly and arcleak as pinned package dependencies.

## Found while looking (2026-11-01)

- A command plugin in the main package cannot use the `Tools/` package's executables without making `Tools/` a dependency, which
  brings its dependencies into ask's resolution: the thing the separate package is for.
- Running `swift run --package-path Tools` from inside a command plugin fails under the plugin sandbox, even with
  `--allow-writing-to-package-directory`: the nested `swift` cannot apply its own manifest sandbox (`sandbox_apply: Operation not
  permitted`) nor write SwiftPM's user caches. So either the plugins run with `--disable-sandbox`, or the entry point is
  `swift run --package-path Tools <command>` with no plugin, or `Tools/` declares the plugins and is run with `--package-path Tools`.
  To choose in the design record.

## Still owed

- A design record choosing the entry point above, then the port, gate first.
