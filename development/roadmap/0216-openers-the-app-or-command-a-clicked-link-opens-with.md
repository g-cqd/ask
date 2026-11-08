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
   - A project file's `openers` is ignored with a notice.
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
