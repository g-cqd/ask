# Antigravity (Cloud Code): what is known and what is not (2026-10-25)

A register of the Antigravity connector's facts and open questions, kept in one place so that a later session does not have to dig them out of
seven ADRs and eight diary files. It is a snapshot: the ADRs and diaries stay the record, this note says where to look and what is still unknown.
Nothing here is a token, a project id, an address or a thinking text; the account's identifiers were never written down.

Each fact carries how it was established:

- **O** observed live, with the owner's Google AI Pro account, under ask's own identity (`ask/0 (Antigravity subscription connector)`);
- **S** a synthetic test only (the server was never made to say it);
- **R** read in source or documentation and not run (pi-integrations, Google's documentation, the `agy` binary's strings).

An unknown has an **id** (`U1`…), what would settle it, what that costs, and who has to say yes. Status of the work itself: roadmap 0052. The work that would settle the cheap unknowns (`U3`, `U6`, `U8`, `U11`) and the one that needs the owner (`U1`) is roadmap 0069.

## 1. What is known

### Sign-in and access

| Fact | How | Where |
|---|---|---|
| The sign-in is Google OAuth with PKCE and a pasted code; the authorize URL equals the one the real `agy` 1.4.6 prints (nine parameters, same order and scopes) | O | ADR-0075 |
| The application's client secret is one of three `GOCSPX-` strings in the `agy` binary, and Google accepts exactly one (`invalid_grant` against `invalid_client` for the others); it is identical in `agy` 1.4.2 and 1.4.6 | O | ADR-0073 |
| All seven requested scopes are granted (two extra aliases); the token's audience is the Antigravity client; access is offline | O | ADR-0075 |
| An access token lasts about 3,300 s and a refresh keeps the **same refresh token** (two observations) and the secret | O | ADR-0075, ADR-0105 |
| A refresh through the shipping binary works end to end, with the record at mode 0600 and the other providers' records untouched | O | ADR-0105 |
| Cloud Code answers to ask's own identity for onboarding, the model list and streaming; the first-party `antigravity/cli/` identity was **never sent** | O | ADR-0080 |
| The host is `daily-cloudcode-pa.googleapis.com`, the one `agy` itself calls; a production host `cloudcode-pa.googleapis.com` exists in the binary | O / R | ADR-0080 |

### Onboarding and the model list

| Fact | How | Where |
|---|---|---|
| `loadCodeAssist` returns the Cloud project as a string, `currentTier` `free-tier` and `paidTier` `g1-pro-tier`; it does so for pi's metadata, without `ideType`, and for `{}` | O | ADR-0080, ADR-0087 |
| `fetchAvailableModels` lists 20 entries and seven role lists; **no entry says it is a chat model**, and display names repeat (four ids are "Gemini 3.5 Flash Lite") | O | ADR-0087 |
| Of the 20 entries, 14 chat candidates answered a trivial prompt (`gemini-2.5-pro` gave 503 "No capacity" twice), the two `chat_*` gave 400, and the `tab_*` and the image model **also answered 200** | O | ADR-0087 |
| Limits: Claude 5.5 1,000,000 in and 128,000 out; GPT-OSS 120B 131,072 and 32,768; Gemini about 1,048,576 and 65,535 or 65,536 | O | ADR-0087 |
| Every entry carries `quotaInfo` with `remainingFraction` and `resetTime`; the values are **identical across the Claude and GPT-OSS entries and identical across the Gemini ones** (0.9967 against 1), which looks like two shared pools | O (the numbers); the reading is **U3** | the fixture strips it |
| An unlisted model id runs and the server answers HTTP 404 "Requested entity was not found." | O | ADR-0098 |

### The stream and the tool loop

| Fact | How | Where |
|---|---|---|
| A stream is CRLF `data:` lines wrapping `{response:{candidates, usageMetadata, modelVersion, responseId}, traceId, metadata}`, ending with an empty text part that carries `finishReason: STOP` | O (12 streams) | ADR-0090 |
| Gemini 3 Flash sends a `thought` part with **empty** text; GPT-OSS sends many non-empty thought parts; Claude sends empty text parts around its call | O | ADR-0090 |
| A Gemini 3 `thoughtSignature` (140 characters) sits on the function call's own part, on the **first call only** of the one parallel pair seen, and on the last text part of a text-only answer | O, one model | ADR-0090 |
| `modelVersion` equals the requested id on Gemini 3 Flash, Claude Sonnet 5.5 and GPT-OSS 120B | O | ADR-0090 |
| A replayed call with no signature is refused on two Gemini 3 models (HTTP 400 "Function call is missing a thought_signature"); the sentinel `skip_thought_signature_validator` and the real signature are both accepted | O | ADR-0080 |
| Claude and GPT-OSS refuse a result without the call's id on `functionResponse` (400 `tool_use_id: Field required`) | O | ADR-0080 |
| ask's eight real tool schemas, sent as `parametersJsonSchema`, are accepted on four models; `{output}` and `{error}` results are accepted | O | ADR-0090 |
| A Gemini history with a signature replays to the same model, to another Gemini model (the sentinel stands in), after a resume in a new process, and to Claude and GPT-OSS (the carrier is dropped) | O | ADR-0090, ADR-0105, diary 2026-10-25-14 |
| `maxOutputTokens` 200,000 on a model that reports 65,536 is accepted | O | ADR-0090 |
| Usage is cumulative per chunk (`promptTokenCount`, `candidatesTokenCount`, `totalTokenCount`); GPT-OSS also reports `cachedContentTokenCount`; `thoughtsTokenCount` was never present | O | ADR-0090 |
| The server mints call ids by family: Gemini `call_<n>`, Claude `toolu_vrtx_…` | O | fixtures |

### Errors, cache and the screen

| Fact | How | Where |
|---|---|---|
| An HTTP error body is `{"error":{"code","message","status"}}` (seen for 400, 404 and 503) | O | ADR-0087, ADR-0090 |
| A model list cached per project lets a run know its window: `gpt-oss-120b` resolved 131,072 and compacted at 85,197; a 1M model kept ask's own 150,000 | O | ADR-0098 |
| The interactive screen shows the provider and model, a tool call, usage, a mid-session `/model` switch Gemini → Claude → Gemini, an abort ("Aborted. Results already known were kept.") and a clean Ctrl-C exit | O | diary 2026-10-25-14 |
| Idle memory is about 56 KiB higher with the connector (six interleaved pairs); no consistent cold-start, input or action difference at load 8 to 15 | O | ADR-0105 |

## 2. What is not known

| Id | Question | Why it matters | What would settle it | Cost and who says yes | Safe default today |
|---|---|---|---|---|---|
| **U1** | What does Cloud Code say when a request is longer than the model's window? | The loop compacts and retries only on a refusal it recognises. `describesContextOverflow` knows "maximum context length", "prompt is too long" and "context…exceed"; a refusal worded as Gemini's public API words it, as I remember it ("the input token count … exceeds the maximum number of tokens allowed"), has no "context" in it and **would not match**. The code reading is certain; the wording is a recollection, so this is a hypothesis, not a finding | One request over the window on `gpt-oss-120b` (about 140,000 tokens), then the wording for Gemini and Claude from documentation or a second request over 1,000,000 tokens (much dearer) | **The owner**: the first request is a large spend of the quota, the second a very large one | The person sees the provider's refusal as an error; with the cache the loop compacts before the window (ADR-0098), without it, never |
| **U2** | What does exhausting the quota look like: status, wording, `retry-after`? | A usage limit must not be retried (ADR-0052 did this for Codex); Antigravity has none | Use the quota up (not sensible), or read a refusal someone else recorded | Not worth a deliberate spend | Treated as a generic status error; may be retried like a rate limit |
| **U3** | What do `quotaInfo.remainingFraction` and `resetTime` mean, and are the pools shared by model family? | A usage line in `ask models agy`, and a usage-limit message that says when it lifts | Read the field before and after a measured amount of use on one model, and see which entries move | Cheap (a few small requests and the list); no approval needed beyond the account's | The field is stripped and unused |
| **U4** | Which tier governs quota, `free-tier` (current) or `g1-pro-tier` (paid)? | What a person can expect to spend | Compare observed limits with each tier's published ones | Reading, not probing; maybe not settleable | Both are stored or ignored; neither is used |
| **U5** | What does an error **inside** a 200 stream look like? | The decoder assumes the HTTP error body's shape | A failure that begins after the first byte (a cancelled upstream) | Hard to provoke on purpose | **S** only |
| **U6** | Finish reasons other than `STOP`: `MAX_TOKENS`, `SAFETY`, `RECITATION`, `MALFORMED_FUNCTION_CALL` | The mapping to stop reasons is Google's documented list | A tiny `maxOutputTokens` (cheap, **settles MAX_TOKENS**); the safety ones are hard to provoke | MAX_TOKENS: trivial, no approval. The others: not sensible | **S** for all but `STOP` |
| **U7** | A blocked prompt (`promptFeedback.blockReason`) | Handled as a refusal with a notice | A prompt the filter blocks | Not sensible | **S** |
| **U8** | A signature on a later parallel call, a signature split across events, and whether the sentinel is needed on **earlier** turns (Google documents the current turn only) | A rejected request in a long tool loop | A parallel call with three calls; a long loop with Gemini 3; a history whose earlier calls carry no sentinel | Cheap, no approval | Sentinel on every earlier turn's first call; works in the loops run |
| **U9** | Does replaying GPT-OSS thought text, or a text-part signature, improve quality? | Possible quality loss; unmeasured | A paired task set | Costly to do well | Neither is sent |
| **U10** | What if `modelVersion` differs from the requested id? | Signatures would stop replaying silently (the sentinel stands in) | Watch for it; a log line on mismatch would make it visible | A small code change | Silent degradation to the sentinel |
| **U11** | What do `thinkingBudget`, `minThinkingBudget`, `thinkingLevel` and `supportsAdaptiveThinking` do on Cloud Code? | ask refuses any explicit thinking level for Antigravity; Claude and Codex have them (ADR-0060) | Send each in `generationConfig.thinkingConfig` on Gemini 3 Flash and read the usage and the thoughts; the Claude and GPT-OSS efforts are in the id | Cheap, no approval | Refused with `ThinkingError.unsupportedProtocol` |
| **U12** | Would the first-party identity change the catalog (pi reports 29 models against 23)? ask sees 20 entries, 15 kept | Which models ask can offer | Send `antigravity/cli/…` once and compare | **The owner**: it is a first-party identity claim, and the project decided not to make one (ADR-0080) | ask's own identity throughout |
| **U13** | Does the production host differ from the daily host? | Whether the daily host can disappear | One `loadCodeAssist` and one list against it | Cheap | The daily host, as `agy` itself uses |
| **U14** | How long does a refresh token live, and is it ever rotated or revoked (two observations of no rotation)? | A silent sign-out | Time, and the unsaved-rotation path already covers a rotation | Time | The unsaved-rotation notice (ADR-0091) covers a rotation that cannot be saved |
| **U15** | The `invalid_client` rediscovery path against the real Google | It is the recovery from a changed secret | Cannot be made to happen without changing the secret | Not provokable | **S** only (ADR-0105) |
| **U16** | Two processes refreshing at once | A wasted refresh, not a wrong one, by the compare-and-replace argument | Two `ask` runs started together with an expired token | Cheap | Argued, not run |
| **U17** | Latency saved by storing the project, and the cost of reading the cache on an `agy` start | Whether the first request should fetch a list | Interleaved timing of `ask --provider agy` with and without both | Cheap; the network dominates | Not measured |
| **U18** | What should a run do with a model the list does not name, or a first run with no list? | A 404 after a request, or a run with no window | A design choice, then a test | Small | The run goes ahead; the 404 is shown |
| **U19** | Should `--model tab_flash_lite_preview` or the image model be refused, allowed with a notice, or silent? | Four entries answer but are not chat models (ADR-0087) | An owner decision | **The owner** | Allowed silently, because nothing refuses an unlisted model |
| **U20** | Gemini 2.x in a tool loop | `gemini-2.5-pro` has answered 503 twice, so the loop has never run on it | Try again at another hour | Cheap, luck | Unknown |
| **U21** | A second Google account, a named connection (`ask login agy --name`), and the account chooser (roadmap 0046) | Whether several accounts can coexist | A second account | **The owner** must have one | Refused; `ConnectionKind` has no agy |
| **U22** | Are the Antigravity subscription's terms satisfied by this use, and can an account be restricted for it? | The most serious risk in the table, and **no probe can settle it** | Reading Google's terms and the product's policy; asking | **The owner** | Honest identity, no first-party claim, the secret read from the user's own `agy` and never shipped |

## 3. Choices that are not facts

These look like facts in the code and are not: each is a decision, recorded so that nobody mistakes it for something the server said.

- The list of chat models is **ask's rule** over a list that marks none (ADR-0087). The `tab_*` and image models answer; they are left out because
  of their limits and role, not because they cannot.
- ask **chooses no model**: the server's own default is an Opus, and spending the person's quota is not ask's call (ADR-0105).
- ask **refuses an explicit thinking level** because none of the fields that might carry one was probed (ADR-0090), not because the server refuses it.
- The **identity string** is `ask/0 (…)`: the version is 0 because ask has none (roadmap 0070).
- The sentinel goes on the **first call of every model turn**, as pi does, not only the current one (**U8**).

## 4. The probes that exist

| Probe | What it covers | Needs |
|---|---|---|
| `Scripts/probe-agy-login.py` | The sign-in's URL and failure paths, no network | the binary |
| `Scripts/probe-agy-provider.py` | Missing model, signed out, reserved name, damaged credential file, no network | the binary |
| `Scripts/probe-agy-live.py` | The interactive screen on the real account (opt-in, `ASK_LIVE_AGY=1`) | the account, `pyte`; it depends on **Esc aborting**, which roadmap 0064 changes |
| `docs/research/probes/Agy*.swift.txt` | The account, cloud, live and loop probes, archived outside the test target | the account |
| `Tests/Fixtures/Agy/` | Six recorded streams, the model list and the onboarding body, reduced: identifiers, free text and quota figures removed | none |

The raw captures (the full model list, the twelve streams, the onboarding body) were kept **outside** the repository, in the author's cache
directory, because they hold the project id and the account's tier text. A later session that needs them must record them again.
