---
status: not-started
blocked-by: []
date: 2026-10-20
---

# 0048 — The input grammar: `/` for commands, `@` for things you point at

People arrive knowing two sigils. This entry fixes what each one means in ask, so the screen has one picker, one set
of rules, and nothing new to learn. It is a design with a prototype behind it, not a feature: nothing here is built.

## The rule

| Sigil | Means | Examples |
|---|---|---|
| `/` | **Do or load something.** | built-in commands (`/config`, `/compact`, `/reload`), skills (`/code-review`), views (`/agents`, `/tasks`, `/sessions`), settings (`/theme`) |
| `@` | **Point at something.** | a file (`@docs/rendering.md:42-58`), an agent (`@reviewer`), an active session (`@session:render-review`) |

Nothing else is a trigger. In particular:

- **No `$` for skills.** Codex uses `$`, but the other five harnesses list skills among their slash commands, and a
  second sigil for the same kind of thing is one more thing to learn.
- **`!` (a shell escape, in Pi) is not decided here.**

A trigger fires only at the **start of a word**. A `/` or `@` inside a word (a path, an address) is just text.

## What the other harnesses do

Opened in a pty on 2026-10-20, **no prompt sent**, so this is what the menus show and not how a turn looks. Items
marked *docs* come from the vendor's documentation, not from running it.

| Harness | `/` menu | `@` | Agents and sessions |
|---|---|---|---|
| Claude Code 2.1.301 | commands and skills together, two-line descriptions | mentions (*docs*) | a panel under the prompt for forks and subagents; opening one sends your messages to it (*docs*) |
| Codex 0.163.0 | `/agents` ("open the agent command center") | file search (*docs*) | `/subagents` switches the active thread (*docs*); skills by `$` or `/skills` (*docs*) |
| opencode 2.0.32 | `/debug /diff /editor /effort /models /thinking /variants` | files and subagents (*docs*) | Tab switches primary agents; child sessions by leader keys (*docs*) |
| Pi | commands with a `(1/50)` counter; skills as `/skill:name` (*docs*) | file search (*docs*) | no built-in subagents (*docs*) |
| Vibe 2.26.1 | commands **and 29 skills**, long descriptions wrapped | not observed | `--agent` at launch |
| Antigravity 1.4.2 | `/agents`, and a skill (`/review-agent`) in the same list; "tab Complete" | not observed | custom agents listed by `/agents` |

What this suggests, and what it does not prove: skills in the `/` list is the common choice. Every harness that lets
you reach a running agent does it by **switching into** it. I found none that lets you **address** a session without
switching, but I did not check exhaustively, so that is a gap to confirm and not a claim of novelty.

## `@` kinds

**A file.** Resolved at send time against the project root, with an optional line range. A path the sandbox does not
let ask read (roadmap 0017) is not offered, and the picker says why. The attachment is data, never an instruction.

**An agent.** A request to delegate. The child inherits the parent's permissions and never widens them (only the user
widens, roadmap 0019), and is read-only unless the user says otherwise. It needs the sub-agent seam roadmap 0027
reserves, which does not exist yet.

**A session.** Your message goes to that session instead of this one. This is the open part, so it gets its own section.

## Talking to another session

The rules the prototype enforces, because getting them wrong would be a security bug and not a cosmetic one:

- **Routing is always visible.** Whenever a draft is addressed, the prompt glyph changes (`›` to `↪`), the status bar
  gains a chip with the target, and the input hint says `Enter sends to <session>`. The picker's detail pane says
  the message goes to that session and not this one. Nothing is sent until Enter; Esc removes the address and keeps
  the draft.
- **Authority travels with the message.** A message the person typed in this screen is user input in the target. A
  message from an *agent* to a session is **untrusted inbound** and must arrive labelled as such, never as user input.
  The transport has to carry the origin, and the target has to show it.
- **A busy target.** Queue the message as a follow-up, or steer at a safe boundary, exactly as for one's own session
  (the `multiline-input` branch is working on steering and queueing).
- **Addressing widens nothing.** The target keeps its own context, permissions and sandbox.
- **Only live sessions are offered.** An entry is probed before it is listed; a dead one is refused with a reason.

Not decided, and each needs its own ADR before code:

- **The transport.** A per-session unix socket in a `0700` directory with a same-uid check; the session store (roadmap
  0008) polled; or an existing channel such as Agora (not evaluated). They differ in latency, in what survives a
  crash, and in how origin is carried.
- **What "active" means** across a reload (roadmap 0041), where the draft is not yet carried over either.

## The picker

One component for `/` and `@`, attached to the input and not floating:

- A title chip and the live filter, then a list with a kind badge per row (`SKILL`, `FILE`, `AGENT`, `SESSION`), and
  a detail pane behind a divider.
- The filter is the text typed after the trigger, and it stays in the draft. **Prefix matches rank first**; the
  prototype's first version put `explorer` above `reviewer` for `re`.
- **Enter inserts or attaches. It never sends.** Esc closes and keeps what was typed. Tab completes.
- With no match, Enter falls through to the existing rule: `/etc/hosts` is still a prompt, and `//word` still
  sends a prompt that begins with a slash (roadmap 0041).
- **The mouse wheel must scroll the transcript, not move the selection.** In the alternate screen, kitty turns the
  wheel into Up and Down keys unless mouse reporting is on, and the prototype's pickers were driven by it until it was.
- Attachments become chips in the input. In the one-row input they sit inline before the text.
- Rows are clickable once the mouse is supported (roadmap 0051, TerminalKit 0016); a click selects as Enter does, and Enter stays the way.

## Names that collide

- A built-in wins. A skill with the same name stays reachable as `/skill:name` (Pi's form). Whether to always show
  that namespace is open.
- **Skills from a project are untrusted until the project is trusted** (roadmap 0039). The picker labels `USER` and
  `PROJECT`, and **selecting a skill grants no tool permission**.

## Done when

- A failing test per rule, in this order: a trigger fires only at a word start; Enter in the picker never sends; a
  path stays a prompt; a skill grants nothing; a draft addressed to a session always shows its route; a dead session
  is refused with a reason; an agent's message arrives labelled untrusted.
- A probe in a real pty covers the picker, including the wheel.
- The transport has an ADR, written before any session addressing is built.

## Evidence so far

The prototype, `docs/prototypes/ui-lab/lab.py`, whose `--check` covers the trigger lifecycle, the routing indicator,
ranking, the wheel, and a negative control for each of the contrast and padding guards.

It is a simulation: no real sessions exist, no transport exists, and none of it has run inside ask's own input. It
was tried in kitty only.
