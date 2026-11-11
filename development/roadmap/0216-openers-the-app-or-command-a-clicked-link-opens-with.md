---
status: in-progress
blocked-by: []
date: 2026-11-08
---

# 0216 — Openers: the app or command a clicked link opens with

The owner, 2026-11-04 (notes n32 and n33, task t215). The decisions are ADR-0148's.

## The configuration

In the user's file only:

```jsonc
"openers": {
  "file": "Xcode",              // an app's name or bundle identifier, per kind of link
  "folder": "Finder",
  "web": "Safari",
  "rules": [                     // the first rule that matches wins, before the kinds
    { "match": { "extensions": ["md"] }, "app": "Typora" },
    { "match": { "pattern": "/work/.+\\.swift$" }, "command": ["code", "--goto", "{path}:{line}"] },
    { "match": { "host": "github.com" }, "app": "Arc" }
  ]
}
```

A rule's `match` takes `kind` (`file`, `folder`, `web`), `extensions`, `host`, and `pattern`, an AemiRegex over the link's target.
All of a rule's criteria must hold. A rule names either an `app` or a `command`.

## The plan

1. **The section** (AskAgentCore):
   - Decode `openers`, kinds and rules, refusing a rule with both or neither of `app` and `command`.
   - Compile patterns once, through AemiRegex, refusing a bad one by name.
   - A project file's `openers` is refused, naming the key, as ADR-0148 says (the plan first said ignored with a notice).
   - Add the catalog and docs.
   - Red first: parsing, refusal, the project's section ignored.
2. **Matching** (pure): from a clicked URI to the opener that applies, or none, with the placeholders' values.
   - Red first: kinds, extensions, host, pattern, the order of rules, and the `-` refusal.
3. **Apps.** `LinkOpener` opens a matched link with the named app (`NSWorkspace.open(_:withApplicationAt:)`), finding the app by
   bundle identifier or name. An app that cannot be found is said in a notice, and the link opens as it would without a rule.
4. **Commands.**
   - The confirmation section shows the argument list and the rule, with allow once, allow always and deny.
   - Grants live in `openers.json` and are revoked in `/config openers`.
   - The launch is detached, with output discarded, and added to the process inventory.
   - Under `--yolo` or `allow-all`, no question.
   - Red first for each, and a PTY probe with a command that writes a file: asked, allowed once, run; then allowed always, not
     asked again; and denied, nothing run.
5. **`/config resolveOpeners`.** Scan the session's rendered links (files by extension, folders, web hosts) and print a proposed
   `openers` section to paste into the user's file. Nothing is written by ask.
6. **Presets, if cheap:** `"command": "vscode"`, `"zed"`, `"cursor"` or `"xcode"` stand for their usual argument lists.

## Done when

Each step's tests pass, and the probe passes while the build before fails it. `docs/screen.md` and `docs/configuration.md` describe
openers, and ADR-0148's safeguards each have a test.

## Not in scope

Opening links on anything but a click; openers for tool output's links beyond what the screen already links.

## Progress (2026-11-08)

- Steps 1 and 2 are done. `openers` is read from your own file and refused in a project's
  (`OpenersConfigurationTests`, red on a stub). `OpenerChoice.choose` picks the first matching rule, then the kind's app, then the
  system's. It fills placeholders in one pass, so a value is never read again, and refuses a value that would start an argument with
  `-` (`OpenerChoiceTests`, 5, red on a stub). AskAgentCore now depends on AemiRegex.
- Nothing calls it yet: a click still opens as before. Next is step 3, apps, through the conversation, which knows the configuration.
- Step 3 is done:
  - A click asks the conversation what opens the link (`Conversation.opening(for:)`), and the conversation answers from the person's
    openers. An app opens the link through `NSWorkspace` with that app, found by bundle identifier or name (`LinkOpenerAppTests`).
    A missing app is said.
  - `ClickedLink(uri:)` reads a clicked URI (`ClickedLinkTests`). A command rule says it is not run yet, until step 4.
  - Found by `probe-openers.py`: no link notice ever reached the status line, so "Not opened" and "Shown in the Finder" were silent.
    They are shown now (`ClipboardNoticeTests`, red first).
  - The probe clicks a missing file under a command rule, so nothing is launched by either build; the build before fails it.
- Not yet: a link's line does not reach `{line}`. Path links leave their `:line` out of the URI, so `{line}` is 1 for now.

## Review (2026-11-11)

- **An app opener opened what would run.** Step 3 took what the system rule only reveals (an app, a script, an executable) and
  opened it in the app the openers name. An app bundle is a directory, so `"folder": "Finder"`, this entry's own example, launched a
  clicked `.app`; a terminal as the file app ran a clicked script. Fixed: an app opener opens only what the system rule would open
  (`LinkOpenerAppTests`, nine cases, red before). **Step 4 must hold the same line:** a command is not offered a target that would
  run, unless the owner decides otherwise.
- **A missing app** only showed its notice. It now opens the link the usual way too, as step 3 says above.
- Still as it was, and said here so it is not taken for done: the app's own failure to open a link is not reported (the call has
  no completion handler), and a rule's pattern is compiled at each click, not once at load.

## The line and column (2026-11-11)

A path's `:12` or `:12:5` reaches `{line}` and `{column}`. The link's address is still the file alone, which is what the terminal
is given; the row it is drawn on says what follows it (`PathLinks.located`), and a click carries the place after the address as
`#L12C5`, which `ClickedLink` reads back and `LinkOpener` leaves out of the file's name. A path wrapped before its place loses it,
and opens at line 1. `LinkLocationTests` (4) and `ClickedLinkTests`, red before.

## Step 4: commands (2026-11-11)

Done, but for the list of what was allowed:

- **Checked when read** (`OpenerRule.problem(in:)`): the program holds no placeholder, a `{word}` that is no placeholder is refused,
  and so is a control character.
- **Asked first** (`OpenerRun.decide`): this time, always, or deny, with the arguments shown each kept apart. Unasked under `--yes`
  or approvals that allow by default; asked every time, with no "always", under `--ask all`.
- **Always** is kept in `~/.local/state/ask/openers.json` (`OpenerGrants`), the person's alone, under the SHA-256 of the command as
  written and the rule's match.
- **Run** by `OpenerLaunch`: no shell, no input, output discarded, a session of its own, the environment commands get; waited for
  two seconds, then left running. A status that is not 0 or a program not found is said.
- **Only what would open**: what would run is still only shown; a file that is not there is not opened (the review's line).
- **The question is the click's, not the turn's**: Ctrl+C denies it and leaves the model alone; a model's question arriving
  meanwhile denies it; a click while another question waits is refused.
- `Scripts/probe-openers.py`, six checks through the release binary with a stand-in command that writes a file: asked, allowed
  once and run with the path and the line, denied, allowed always and kept, not asked again, and unasked under `--yes`. The build
  before fails the first.

## Still owed

- Steps 5 (`/config resolveOpeners`) and 6 (presets) are **proposals of mine, not the owner's asks** (white paper §7, 2026-11-11):
  not built, and not scheduled until the owner has refined or dropped them.
- The owner's answer on whether a rule may open what would run in an editor; today it may not.

`/config openers` is done (2026-11-11): it lists what was allowed always, numbered, and `/config openers revoke N` or `revoke all`
takes it back (`OpenerGrantsTests`; the probe's seventh and eighth checks). Step 4 is complete.
