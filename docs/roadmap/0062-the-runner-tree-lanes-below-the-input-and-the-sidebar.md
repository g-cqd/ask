---
status: in-progress
blocked-by: ["0064"]
date: 2026-10-24
---

# 0062 — The runner tree: lanes below the input, focus, and a sidebar

The owner wants agents, and the subagents of subagents, visible below the input as Claude Code shows them, **focusable**, and as a **tree in a
sidebar** too. Today ADR-0066 shows a flat count and a list of background jobs. This entry turns that list into a tree with three views, and does
it **before** any subagent exists, with jobs as the runners, so the whole UI is verifiable against real processes first. Design and open
questions: `docs/research/skills-and-agents-design-2026-10.md`.

**Step 1 built** (2026-10-25, ADR-0105, diary 2026-10-25 (18)): the cached tree and capped below-input strip, status counts from the same tree, and Esc closes
it without losing the draft. Real jobs remain roots; nested snapshots are tested. Steps 2–4 (focus/output, approvals and sidebar) are not built. The key ladder
of 0064 is built; its lane-return behavior will be implemented with step 2 here.

## One model, three views

`RunnerInfo` (ADR-0066) gains an id, a parent id (nil at the top), a kind (`job` now, `agent` with 0063), a state (`running`, `waiting for
approval`, `done`, `failed`, `stopped`) and one line of what it is doing. The composition root sends the whole tree. The status line's count,
the lane strip and the sidebar are views of it and cannot disagree.

## Steps

1. **The tree and the strip, jobs only.** The model above; a lane strip of one row per runner below the input, indented by depth, text only,
   taking rows from the transcript with a cap and `… N more`; it replaces ADR-0066's list above the status line (`/tasks` still opens it).
2. **Focus** (the owner's refinement, 2026-10-24). Focus decides what the transcript shows and where the input sends. There is **one input slot**,
   and it sends to the focused lane; a lane has no input of its own. **Down from an empty draft, or from the last line of a draft**, moves a
   selection into the strip; Up and Down move; Right expands and Left collapses; **Enter on a selected lane focuses it**; **Esc returns focus to the
   input, always, and from the input goes back to the main lane** (roadmap 0064: Esc never aborts); a **click on the input returns focus to it**;
   `/agents` lists and `/agents NAME` focuses; a click on a row focuses it. The route is always in text: `main › reviewer › explorer` in the status line and the target in the prompt label.
   A job has no conversation to focus, so for jobs focus shows its output; for agents (0063) it shows the child's transcript.
3. **Approvals follow the lane.** A question from a runner surfaces at the current focus, never waits unseen: the strip row says `waiting for
   approval`, the status line counts it, the answer keys are the existing ones, and the question names the lane.
4. **The sidebar** (the *workbench* layout of 0015 and ADR-0046), built for the **character layout first**: the same tree, the same keys and
   clicks, a divider that is also the scrollbar track. **Open by default in the workbench layout, and toggleable** (the owner's answer). Pixel strokes come later and change only the divider; it does not wait for 0014 or 0003.

## Rules that must hold, each with a failing test first

- The strip, the sidebar and the status count are computed from one tree: a test changes the tree and checks all three.
- Indentation shows depth for any depth; collapsing a node hides its descendants and keeps their count in the parent's row.
- Nothing is sent to a runner that is not shown: the target is in the screen's text whenever the input would send anywhere but main.
- Esc returns focus to the input from the strip or a focused lane, and from the input to the main lane, and does nothing at main; focus on a runner
  that ends returns to main with a notice, never to a blank lane. A click on the input returns focus to it.
- One input slot: nothing a lane shows has an input of its own, and what is in the draft goes to the focused lane.
- A question from an unfocused runner is visible in the strip, the sidebar and the status line, and answering it from main works.
- Every click has a key (ADR-0044's rule): focus, expand, collapse and return.
- With no runners, the strip takes no rows and the screen is what it is today.

## Probes

- A real PTY probe with real background jobs: the strip appears, a job's output can be focused and left, `/agents` lists, a click and the key
  do the same thing, and the screen after Esc, Esc is the screen before.
- Cost: rows taken from the transcript, per-frame cost with 0, 5 and 50 runners, same harness before and after, with the machine's load noted.

## Done when

All four steps are built, the rules have tests that failed first, the PTY probe passes, and the frame benchmarks show no regression with no
runners. Subagents (0063) then supply `agent` runners with no change to this UI.

## Not decided here

The sidebar's width, what "context" lists, and the key that toggles the sidebar.
