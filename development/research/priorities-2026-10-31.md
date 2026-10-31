# Roadmap and wishes reassessed (2026-10-31)

Supersedes the order in `priorities-2026-10-30-evening.md`, which is done: 0158 to 0169, 0117's redesign, 0021, 0153's defaults and
the `/reload` signature check, 0166. Every wish in the wishes file (119 lines) has an entry, and most of the interface wishes are done.
The owner agreed to this order on 2026-10-31 ("go ahead, seems nice").

## Next, in order

1. **A: the records.** Close what is built (0049, 0075, 0077, 0079), mark what waits on an account (0034, 0040), land through
   `Scripts/land.sh` once (0068), and finish 0101's guard against new subprocess calls.
2. **B: accounts and scopes.** 0092 (a second login adds an account; done) with 0046 and 0047's leftovers, then 0094 (the user's file
   limits which providers a repository sees, by path, remote or git identity; done, ADR-0137).
3. **C: keys and security.** 0110 (the Keychain by default; first signing done 2026-10-31, by hash, see the record), then 0153's open findings.
   Done 2026-10-31: the Not-covered audit (run 2), six findings fixed, see `security-audit-2026-10-31.md`.
4. **D: tokens per turn.** 0137: measure what the tool definitions cost per request, then cut.
   Measured 2026-10-31 (`tool-definition-sizes-2026-10-31.md`); the two large cuts wait on the owner, see the record.
5. **E: interaction.** 0116 (one confirmation picker, reusing 0117's lane), then 0078 (tool blocks without section labels).
6. **F: larger.** 0152 with 0087 (syntax highlighting, Atelier's lexers promoted first), and a design entry for 0115 (taking over a
   running session).

Parked until asked: 0088 (deferred by the owner), 0109, 0130, 0122, 0121, 0135, 0140, 0149, 0150, 0020, 0022, the pixel work (0003,
0012, 0014, 0015), 0070, 0032, 0063, 0107, 0055. Ongoing, the owner's: 0071 (daily use and a defect log).

## Real-terminal checks

Each is built and checked in a PTY or pyte, never in the owner's terminal. One sitting covers them all.

- Shift-Enter from a physical key inserts a newline (0049).
- A click on a path or a web address in a tool block opens it; hovering one copy of a path lights only that copy (0075).
- Folding and unfolding blocks with the mouse, on a long session (0079's fold behaviour).
- The question lane: Tab through tabs, choices and the note; Space selects; the draft below is kept (0117).
- A block changed in place keeps one blank row before the next (0168); an open thinking block's first row carries its status (0169).
- Markdown in reasoning, in the person's messages and in the draft (0151).
- `/reload` between two builds signed with the personal identity (0153): done by probe H4, 2026-10-31.

## Waiting for the owner

- **The first signed run on the real credentials** (0110): signing is done, by hash (`0F1D77299FF47DC421EF91FB51DB0083C6B2FEC5`,
  the valid certificate of team L2LRQKFJ3U). The owner's next run of a signed build moves the secrets into the login keychain;
  check with `security find-generic-password -s ask`.
- **The pin cascade** (0166): `Scripts/update-pins.py --apply` when aemi and AemiRegex are quiet.
- **0092:** when two accounts serve one model, ask each time or remember a default per model. Built as "ask once, remember per model,
  change with `/model`" unless the owner says otherwise. Done in `afa33d4`; `--model` keeps the default's account rather than
  refusing a shared model, so no script breaks.
- **0127:** whether a "replace" layer setting is wanted. **0148:** the keep-awake restart test. **0117:** whether a single question
  sends on Enter without the review.
- **From 0079:** whether the citations of `g-cqd/pi-integrations` (public, cited as provenance) stay; and an ADR recording that the
  Copilot connector presents itself as VS Code at the owner's request, the service's terms being the owner's call.
