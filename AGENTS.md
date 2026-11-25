# Working in `ask`

Terminal coding agent for macOS written in Swift 6 (`g-cqd/ask`).

## Engineering principles

- **Verify claims with executable checks.** Every behaviour change and bug fix requires a test; performance claims require measured before/after data.
- **Strictness.** Swift 6 language mode, strict memory safety, warnings as errors. Keep core modules decoupled from terminal/UI details.
- **Security & confinement.** Respect Seatbelt sandboxing, command policy gates, Keychain credential storage, and secret-free logs/sessions. Never bypass confirmation or sandbox boundaries.
- **User documentation tracks code.** Every configuration key in `ConfigurationFile` must be documented in `docs/configuration.md` (enforced by `UserDocumentationTests`). Keep `README.md`, `docs/`, and `Package.swift` factual and free of roadmaps or diaries.

## Commands

```sh
swift test
swift build -c release --product ask
swift format lint --strict --recursive Sources Tests Package.swift
```

## Architecture & Formal Models

- Architecture decision records: `docs/adr/`
- Formal TLA+ and Lean models: `docs/formal/`
- Protocol extensions: `docs/protocol/`
