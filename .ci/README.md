# CI

`.github/workflows/ci.yml` calls the family's pinned swift-ci workflow, configured by `action.json`, then measures the
performance budgets on a PTY (reported, not enforced: ADR-0122). `mutation.yml` runs mutation testing nightly.
`Scripts/quality.sh` runs the same quality checks locally (`.ci/swift-ci run quality`) and the release tests.

Each change runs quality — swift-format, SwiftLint metrics, the pinned analyzers over `Sources` and `Tests`, then
`Scripts/dependency-audit.sh` and the script, record and layering guards — and the macOS debug and release tests.
ask is macOS-only, so there is no Linux leg; the sanitizers run nightly or manually.

The analyzers report notes only today, so there is no baseline. The library discipline (`quality.discipline`) is off:
ask is an application, and turning it on means first clearing what it finds (force unwraps and a force try in
`Sources`; untyped `#expect(throws:)` and wall-clock assertions in `Tests`).
