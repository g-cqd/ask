# A rationalisation pass: the architecture, how features are proposed, and where the project disagrees with itself (2026-11-08)

The owner, 2026-11-08 (note n53): "we need to do a rationalization pass on the project architectures, how we propose features and
where are some inconsistencies and how we could add to the roadmap relevantly". This note records what was counted on `main` at
`427a7d05`, says what is inconsistent, and proposes roadmap entries 0209 to 0212. Every number below came from a command run that day
(`find`, `rg`, `git log`), not from memory.

## 1. The shape today

| Target | Files | Lines | Depends on (of ask's) |
|---|---|---|---|
| ask (executable) | 138 | 8 925 | all seven |
| AskAgentCore | 343 | 17 807 | AskAI |
| AskAI | 265 | 12 718 | none |
| AskTUI | 212 | 13 100 | none |
| AskTools | 108 | 6 833 | AskAI, AskAgentCore, AskMCP |
| AskMCP | 41 | 2 173 | AskAI |
| AskApple | 9 | 580 | AskAI, AskAgentCore |
| AskCore | 3 | 131 | none |

Tests: 663 files in seven targets. 92 PTY probes in `Scripts/probe-*.py`. 146 ADRs, 208 roadmap entries, 198 diary files.

The layering holds: no cycles, the TUI knows nothing of the agent, and the executable is the only place they meet. AskCore is
named like a shared foundation but holds only the launch budgets and the process environment, and only the executable imports
it. The rest of
this note is about what that layering costs, and about the documents around the code.

## 2. Inconsistencies in the code

### 2.1 One setting is written in about eleven places

`ui.dim` (a2a1b71c) touched: `DimPreference` (AskAgentCore), the `UISection` field, `UISection.keys`, `layered`, `value(forKey:)`, the
decoding in `ConfigurationFile+UI`, its `SettingCatalog+UI` row, `docs/configuration.md`, `ScreenDim` (AskTUI), `ScreenOptions`,
the mapping in `Sources/ask/RunSettings+Screen.swift`, and the `ConfigurationKeySourceTests.full` fixture.

Seven `*Preference` enums in AskAgentCore have a twin in AskTUI (`ScreenDim`, `SpinnerStyle`, `TimeoutDisplay`,
`QueuedAfterInterrupt`, `ScreenAppearance`, …), bridged by `rawValue` in `RunSettings+Screen.swift`. The twins exist because AskTUI
depends on none of ask's targets. Tests catch a key that is missing from the catalog or the documentation, but not a twin whose
cases drift from its pair: the `rawValue` bridge falls back silently.

Each step is small, but together they are the main cost of adding a setting. A mutation run on 2026-11-08 found two `value(forKey:)` arms
that no test read.

### 2.2 Slash commands are declared twice and dispatched by string twice

- **Declared:** `ScreenController.builtIn` (AskTUI) and the conversation's table in `AgentConversation+Commands` (ask).
- **Dispatched:** by `switch` on the name in `ScreenController+Submit` (12 cases) and `AgentConversation+Commands` (20 cases).
- `thread`, `rename`, `merge`/`close` and `reload` appear in both switches: the thread lane catches them first and forwards some
  by name (`.runCommand(name: "reload", …)`).
- A name in a table with no case in a switch, or the other way round, is found only by using it.

### 2.3 Suppressions in data tables

There are 323 `@dl:accept` comments. The densest files are tables: 17 in `AgentConversation+Commands`, 15 in `ConfigurationFile`, 13 in
`UISection`, and 10 in the roughly 35 lines of `ScreenController.builtIn`, where each entry carries a comment explaining why two
entries look alike. The duplicate detector fights data. One registry (2.2) and one setting declaration (2.1) remove most of these;
the rest suggest letting the detector skip array literals of one initialiser.

### 2.4 Verification that lives outside the repository

- **The PTY probes are not in CI.** `ci.yml` and `mutation.yml` run none of the 92 probes, and the script that runs them all lives in a
  temporary directory on one machine. This week the probes found three defects that the unit tests missed: an underline lost
  in the colon form of SGR 4, a tab row clipped silently, and back-tab doing nothing outside the kitty keyboard protocol.
- **The mutation gate had no green scheduled run from 3 to 8 November.** Each run failed for a different reason: the tools version,
  then the build timeout, then the source standards failing on the tool's rewritten files, then two real survivors. All are fixed
  now (24754a72, 427a7d05). Nobody saw it fail for five days.

## 3. How features are proposed

Work enters through four trackers that point at each other:

1. The owner's notes (n-numbers).
2. The agent's task list (t-numbers), which is kept outside the repository yet cited in roadmap entries.
3. The roadmap (NNNN).
4. The diary and the ADRs.

What goes wrong:

- **No common shape.** The section headings vary: `Done when` (58 entries), `Still owed` (38), `The plan` (28), `Plan` (14),
  `The work` (11), `What is built` (10), `What lands` (7). Some entries open with the owner's words, others with the design.
- **In-progress is where entries stay.** Of the 208 entries, 133 are done, 45 in progress and 30 not started. 20 of the 45 have no
  section saying what is still owed, so "in progress" cannot be checked. Some were last touched on 28 October.
- **Other repositories' work.** About thirteen entries describe another repository's work: 0139 (AemiHTML), 0196 to 0204 and 0206
  (AemiMermaid, AemiMarkdown, TerminalKit, MarkdownLook), and 0207. Their status is ask's, but their code is elsewhere.
- **Features land with no entry.** `ui.dim` landed with neither an entry nor an ADR.
- **The diary stopped.** The last diary file is 2026-11-04, yet 22 commits touched `Sources` since 5 November. The white paper calls
  the diary "where probe history lives", and the probe history of those days is only in commit messages.

## 4. Proposed roadmap entries

| Entry | Title | Removes |
|---|---|---|
| 0209 | One declaration per setting | 2.1, most of 2.3 |
| 0210 | One registry of slash commands, with typed handlers | 2.2, the rest of 2.3 |
| 0211 | The PTY sweep runs in the repository and in CI, nightly | 2.4 |
| 0212 | Roadmap hygiene: one template, a triage, and a generated index | 3 |

Each one is a separate file, not started, and none blocks another. 0209 has a decision in it for the owner (below), so it starts with an
ADR.

## 5. Questions for the owner

1. **May AskTUI depend on a leaf target of shared vocabulary?** Either AskCore (131 lines, no dependencies, imported today only by
   the executable) or a new leaf target. If AskTUI could use it, the shared value types
   (`Dim`, `Spinner`, `Appearance`, …) would live there once and the `rawValue` bridge would go away. If not, 0209 generates the
   twins and a test checks them against each other. Either way it needs an ADR.
2. **Should other repositories' entries move to those repositories?** The proposal: each one becomes a pointer in ask's roadmap,
   with status `done` once it moves, and the tracking lives with the code.
3. **Is the diary still wanted daily?** Or should commit messages and the roadmap's progress sections replace it? The white paper
   (§4) would change accordingly.
