# Which tools models call wrongly, read from real sessions (2026-11-17)

The owner (2026-11-17): what models are told about the tools could be better, and with no user base relying on a tool's shape, tools
that do the same thing could be one. Before changing a word: where do models go wrong today? Measured with
`Scripts/measure-tool-errors.py` on this machine's sessions, read only: 197 files from 2026-10-26 to 2026-11-17, none compressed
or encrypted, **47,074 calls, 1,780 of them answered with an error (3.8%)**. The models are mostly Claude's, with local ones in
the early sessions; the counts are not split by model.

A failed call is sorted by what it said: its **arguments** were refused; something was **not found** under the name given; a
command was **checked** and refused before it ran; or the call was right and the **outcome** was a failure (an exit status, a
timeout, a 404).

| Tool | Calls | Failed | Arguments | Not found | Checked | Outcome |
|---|---|---|---|---|---|---|
| `bash` | 38,729 | 1,479 | 0 | 0 | 552 | 927 |
| `read` | 4,127 | 125 | 0 | 118 | 0 | 7 |
| `write` | 1,496 | 12 | 7 | 3 | 0 | 2 |
| `tasks` | 1,002 | 43 | 42 | 0 | 0 | 1 |
| `job` | 560 | 58 | 0 | 10 | 0 | 48 |
| `notes` | 451 | 6 | 6 | 0 | 0 | 0 |
| `question` | 253 | 6 | 6 | 0 | 0 | 0 |
| `wait` (a tool since folded into `job`) | 42 | 23 | 0 | 0 | 0 | 23 |
| `edit` (since folded into `write`) | 29 | 5 | 5 | 0 | 0 | 0 |

`bash` is 82% of every call. `skill`, `search_session` and apple-docs's tools (about 280 calls together) never failed.

## What the failures say

1. **`bash`, 269 commands refused by shellcheck**, and rising: 97 of 28,492 calls in the second half of October (0.3%), 172 of
   10,215 in the first half of November (1.7%). Three findings are nine in ten: `ls | grep` (SC2010, 147), `cd` without
   `|| exit` (SC2164, 44), an unquoted `$(…)` (SC2046, 43). The tool's description says nothing of a check: a model learns it by
   being refused, each session again. Each refusal is a round trip.
2. **`bash`, 271 `fish:` syntax errors**, all on 2026-10-28 and 29, when commands ran in the person's login shell. Gone since the
   shell is chosen (ADR-0126) and named in the description: an example of a description curing a class of failure.
3. **`read`, 118 files not found; of the 114 "No file at", 90 gave a relative path.** Paths such as `ask/Sources/…` from inside
   `ask`: a model unsure of where it stands. The working directory is in the system prompt, and no parameter says what a path is
   relative to.
4. **`tasks`, 42 refused calls of 1,002 (4.2%), the highest rate of a tool in use.** 28 are a title over 120 characters, a limit
   the description does not give; 7 are `edit` given a `state` (another operation's field); the rest are fields on the wrong
   operation (`move` with several ids, `add` with `before`). The description does not say which operation takes what.
5. **`question`, 5 headers over 12 characters.** The limit is in the description and in the schema (`maxLength`); models still
   exceed it now and then.
6. **`job` and `wait`, 71 failures that are not the model's**: `[job-N ended]` and `[job-N ended: exit N]` are marked as errors
   when a wait finds its job over. Whether a job ending is an error is a behaviour question, not a wording one: for the owner.
7. **`write`, 7 `old_text was not found`** in 1,496 calls: rare.

## What the model is told today

From the first request of `ask -p hi` on `97d9ffd2` (10 tools, 8,028 characters of description and schema):

- Of 46 top-level parameters, one has a description (`sandbox`). Everything else is in each tool's one paragraph: `read`'s
  explains twelve parameters in three sentences.
- **The system prompt names tools that no longer exist**: "use wait, job_input and job_stop". They are `job`'s actions since the
  tools were folded.
- `write` offers two ways to overwrite a file (`content`, or `new_text` alone).
- `tasks` and `notes` describe `changes` and `read` nowhere but in the paragraph, and their operations' fields not at all.

## Which arguments are given

`Scripts/measure-tool-arguments.py`, the same sessions on 2026-11-17 (47,227 calls), read before consolidating anything:

| Tool | Calls | What is given |
|---|---|---|
| `write` | 1,496 | `content` 1,103; `old_text` with `new_text` 392; **`new_text` alone 1** |
| `bash` | 38,915 | `timeout_seconds` 20,495; `yield_seconds` 2,286; `sandbox` 840; `wait_for_port` 26, `wait_for_output` 7, `wait_for_file` 1 |
| `job` | 561 | `wait` 472, `stop` 65, `status` 22, **`input` 0**; `wait_for_file` 2, the other two waits 0 |
| `read` | 4,141 | `offset` 289, `limit` 320; **the eight PDF and video arguments 0** |
| `tasks` | 1,011 | `changes` 562, `read` 195 (the rest an earlier shape) |
| `notes` | 457 | `read` 340, `changes` 123 |
| `narrow_sandbox` | 5 | `reset: true` 4, `sandbox` 1 |
| `search_catalog`, `server_resource`, `dispatch_call` | 4, 2, 0 | |

Read with care: these are one person's sessions on a Swift codebase with few PDFs, no video, and MCP servers connected on
few days. An argument never given here is not an argument nobody needs; it is one whose bytes were paid 47,227 times for nothing
in this use.

## Not measured

- Calls that succeeded and were still the wrong call (a `bash cat` where `read` was meant, a whole file rewritten where an edit
  would do): the sessions record no intent.
- The same counts by model.
- Whether a better description lowers any of these: only sessions after the change can say, with this script.
