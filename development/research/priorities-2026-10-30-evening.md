# Roadmap and wishes reassessed (2026-10-30, evening)

Supersedes the order in `priorities-2026-10-30.md`, whose first four items are done: the naming table and the renames (0154), the
showcase (run by the owner, works), the close-out pass, and the question tool (0117, but for clicks). The roadmap holds 164 entries: 87
done, 33 in progress, 44 not started. The wishes file (116 lines) gained one wish at 16:36, filed as 0164; every wish has an entry.

## What the state says

1. **The owner now meets slowness, not missing features.** Two of the 14:43 wishes are seconds-long stalls on long sessions: unfolding a
   block near the top (0158) and `/tree` (0160). The action budget is 8 ms; these are 250 to 600 times over it, and they hit every long
   working session. An unfold changes one block's revision, so the cost is in how the transcript recomputes heights and offsets after
   it, which `/tree`'s rebuild most likely shares.
2. **Approvals are now frequent, so losing them hurts.** Since 0134 and 0156 commands ask; a `/reload` (which the owner uses while
   developing ask) forgets every "allow for the session" answer (0159).
3. **Small, visible gaps in how a stop is shown** (0162, 0163) were each reported once; they are cheap and fit one session together.
4. **New settings keep arriving** (0164 adds two keys) while each key is still written in four places by hand (parser, `/config`
   editor, `ask config`, docs). 0118 with 0096 removes that, and is cheaper the earlier it lands.
5. **Two budgets are over:** actions on long sessions (above) and active memory (0088, 21.5 MiB against 20). Step 3 of 0088 (payloads on
   disk) touches the same transcript code as 0158, so it should follow it.

## Next, in order

1. **0158 and 0160 together: long sessions stay responsive.** First a measurement in `Scripts/measure-long-session.py` for an unfold
   near the top and for `/rewind N` on a session of 30,000 lines (red: over 8 ms), then the fix where the measurement points, then the
   same numbers green.
2. **0159: `/reload` keeps the session's approvals**, red first with a probe that answers "for the session", reloads, and runs the same
   command without a question.
3. **0162 and 0163: stops shown plainly**: `[interrupted]` in a stopped block's status, and one message instead of a half-written
   reasoning block.
4. **0118 with 0096: one settings list** feeding the parser, the editor, `ask config`, the docs and a generated example; then
5. **0164: a colour per session**, built on that list (its keys proposed in the entry, to settle with the owner).
6. **0117's rest:** clicks on choices and tabs, and a showcase scene for the questions.
7. **0088 step 3: payloads on disk**, after 0158 has settled the transcript's layout code.
8. **0153's rest:** finding 5 (`ask -p` passes control sequences, OSC 52 among them), the hardening notes, the default network.
9. **0113:** commands take effect at the next turn.

## Owner steps

- One live request on the Claude subscription with a search-mode MCP server (Xcode's), to confirm the renamed tools pass (0144).
- Two choices in 0117 to confirm: one question sends without a review; Space checks only while the note is empty.
- Whether the gate builds the Benchmarks package, about a minute per run (0028).
- Signing a build for the Keychain (0110); the restart test for `keepAwake` (0148).

## Later or parked

Unchanged: setup allowances (0155), pixel UI (0014, 0015), isolation (0020 to 0022), Aemi promotions without a consumer (0076, 0087),
AskMCP conformance (0123), subagents (0063), Xcode's code model (0073), taking over a session (0115), distribution (0070), session
conversion and the tool middleware (0149, 0150), Protobuf, MDM, Linux and Windows, compiled plugins, Mermaid, codemode, AemiHMMML.

## Update (2026-10-30, later)

Done since: item 1 (0158 and 0160, `60c2038`): an unfold at the top of a 23 MB session went from 2253 ms to about 3 ms, `/rewind 170`
from 6 to 11 s to 0.3 to 0.4 s. No new wish; 89 done, 33 in progress, 42 not started.

What changed in the order:

- **0159 is half built** (the file that carries the grants to the new process, with its tests, uncommitted): finishing it stays next.
- **The owner reported test runs exceeding memory.** Measured: no test target over 310 MiB at run time, the release test build of the
  gate under 2 GiB, mostly in compiling AskAITests; not reproduced. It stays a question to the owner (which package and command) before
  any work; if it is the release test build, the remedy is the gate's test configuration (testing in debug, or fewer parallel jobs),
  to be decided with the owner since the gate tests in release on purpose.
- **`/rewind` is still 300 to 400 ms** against an 8 ms action budget: the history is re-read and re-applied whole. Not urgent now that it
  no longer blocks typing; recorded in 0160.
- **0144's live check is now possible**: Xcode's server is enabled in the owner's file.

The order from here is unchanged: 0159, then 0162 with 0163, then 0118 with 0096, then 0164, 0117's clicks, 0088 step 3, 0153's rest,
0113.

