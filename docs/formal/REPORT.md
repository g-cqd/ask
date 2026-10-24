# Formal modelling of ask: report for the maintainers

Date 2026-10-24. Branch `formal-models`, from `bdc84df`. Everything here is in `docs/formal/`, `Tests/`, `docs/roadmap/0056`,
`docs/roadmap/0057` and `docs/diary/2026-10-24-29.md`. No production code was changed.

## Summary

Three faults confirmed, one of them a user-visible sign-out. Each has a model that shows it, a test that reproduces it in ask's
own code, and a roadmap entry.

| # | Fault | Severity | Found by | Tests (all `withKnownIssue`) | Roadmap |
|---|---|---|---|---|---|
| 1 | A failed save after a successful token refresh leaves the spent refresh token stored; the next run is refused and told to `ask login` | Medium | TLA+/TLC | `ClaudeRefreshSaveFailureTests` (2) | 0056 |
| 2 | `Job.wait(for:)` can report `found` for text the command never printed | Low | Lean 4 | `OutputBufferTests`, `JobFalseFoundTests` (2) | 0057 |
| 3 | Cutting output at a byte shows U+FFFD where valid UTF-8 was printed | Low | Lean 4 | `OutputBufferTests`, `ClippedTextTests` (2) | 0057 |

A `withKnownIssue` test records the failing expectation and passes today. When the fix lands the expectation passes, Swift Testing
reports "known issue not recorded", and the test tells you to delete the wrapper.

## 1. A transient save failure signs the user out (0056)

**Where.** `Sources/AskAI/Claude/ClaudeAccess.swift` `auth(now:)`, and `CodexAccess.credentials(now:)`, which has the same lines.

**What happens.** The refresh token is single use (ADR-0073). `auth` takes the refresh lock, reloads, calls the server, which accepts
the old token and issues a new pair, then saves under the save lock with `saveClaude(_, ifStill:)`. If that save throws
(`CredentialFileError.locked` after the 5 s wait, a full disk, a failed rename), `auth` throws `.storage` and drops the response.
The file still holds the token the server has now spent. The next ask offers it, gets `invalid_grant`, and prints
"run `ask login claude` again".

**Model.** `docs/formal/CredentialRefresh.tla`, hand-written from the two files above and `CredentialFile.swift`. Two runs, up to two
sign-ins and sign-outs, one refresh lock, a server that accepts each token once.

- `MaySaveFail = FALSE`: 317 states, 215 distinct, **no violation** of `OneRefresher`, `NoDoubleSpend`, `StoredTokenUsable`,
  `SignOutStands`. The lock and compare-and-replace design is sound for the steps it models.
- `MaySaveFail = TRUE`: `StoredTokenUsable` violated in four steps: lock, reload, server accepts, save fails.

**Reproduction in code.** `Tests/AskAITests/ClaudeRefreshSaveFailureTests.swift`. Another ask holds the save lock
(`CredentialLock.acquireBlocking(..., name: "write")`) past the file's `lockWait`; the scripted server answers the refresh; `auth`
throws `.storage(.locked)`; the stored token is still `OLD`; a second `auth` sends it and the server refuses it.

**Not tested.** Codex. Antigravity does not rotate its token (diary 2026-10-24-23), so it is unaffected.

**Suggested fix.** Retry the save before giving up; if it still fails, say that the credentials were rotated and could not be
stored, instead of the generic storage error. Returning the fresh access token for the current request is a separate choice: it
serves this request and leaves the next one signed out.

## 2. `wait` can find text that was never printed (0057)

**Where.** `Sources/AskTools/OutputBuffer.swift` `kept`, searched by `Job.wait(for:)` in `Job+Waiting.swift`.

**What happens.** The buffer keeps the first and last `keeping` bytes of the unread output and counts the middle. `kept` is
`head + tail`, which closes up the gap, so a needle that straddles the join matches. The streaming path in `Job.received` uses real
contiguous windows and is correct; only the check at the start of `wait` uses `kept`.

**Reach.** `BashTool.keptBytes` is 512 KiB, so it needs over 1 MiB of unread output and a needle landing on the join. Rare, and the
result is the model being told a server is ready when it is not.

**Model.** `docs/formal/lean/OutputBuffer.lean`. Proved: `kept` and `omitted` account for every byte, `kept` is at most `2k`, a stream of
at most `2k` is kept whole. Refuted by `decide`: `[5,6]` is a run of `kept 2 [1,5,9,9,9,9,6,2]` and not of the stream.

**Reproduction.** `OutputBufferTests` (the buffer alone) and `JobFalseFoundTests` (a real job printing `abRezzzzzzzzadcd` with
`keeping: 4`, then `wait(for: "Read")` returns `.found`).

**Suggested fix.** Search the head and the tail as two runs, with the carry the streaming path already keeps.

## 3. Byte cuts split characters (0057)

**Where.** `OutputBuffer.text` and `Compaction.clipped(_:toBytes:)`.

**What happens.** Both take a byte prefix and a byte suffix and decode them with `String(decoding:)`. A character of two or more bytes
that straddles a cut becomes U+FFFD, so the model reads garbage where valid UTF-8 was printed (here, `é`).

**Reproduction.** `OutputBufferTests` and `Tests/AskAgentCoreTests/ClippedTextTests.swift`.

**Suggested fix.** Move each cut to a scalar boundary; at most three bytes of budget are lost.

## Read and not modelled

- `OutputBuffer(keeping: 0)` traps (`% keeping`, then an index). Unreachable while the only caller passes a constant. No test.
- `SessionFile.begin`: when `SessionLock.adopt` throws `.inUse`, the descriptor `writeExclusively` returned is not closed.
- `SessionFile.rewrite()` links a `.damaged` backup before the rename, so each failed rename leaves one more until
  `preserveOriginal` runs out at 1,000 and the session can no longer persist.
- `SessionFile.append` / `rewrite`: when the flush or the directory flush fails after the bytes are written, the record is on disk and
  memory rewinds it, so a crash before the next rewrite resumes a session containing a message the user was told failed.

None of these four was probed.

## Checked and found sound

- **Queued input (ADR-0040).** Read against `PromptQueue`, `AgentLoop.run`, `ScreenController+Queue` and `ScreenSession`: acknowledgments
  precede `runEnded` in the update stream, the screen keeps its copy until acknowledged, and `endRun` starts or returns whatever is
  unacknowledged, so the final-boundary race is closed. Not modelled in TLA+, so this is a reading, not a check.
- **Job waiters.** `Job.wait` registers under the same lock that tests the status and the cancellation flag, so neither a missed wakeup
  nor a double resume is possible. Also a reading.
- A run that finishes on the last allowed turn with input queued throws `turnLimit`. `SteeringTests` pins this as intended; whether a
  finished run should report an error is a design question, not a defect found here.

## How to run

```sh
java -cp tla2tools.jar tlc2.TLC -deadlock -config CredentialRefresh.cfg CredentialRefresh.tla     # clean
sed 's/MaySaveFail = FALSE/MaySaveFail = TRUE/' CredentialRefresh.cfg > /tmp/fail.cfg
java -cp tla2tools.jar tlc2.TLC -deadlock -config /tmp/fail.cfg CredentialRefresh.tla              # violation, 4 steps
lean docs/formal/lean/OutputBuffer.lean                                                             # silent: all proofs and decides hold
swift test -c release --enable-testable-imports \
  --filter "ClaudeRefreshSaveFailureTests|OutputBufferTests|JobFalseFoundTests|ClippedTextTests"
```

TLC 2.19, Lean 4.35.0. Both models can fail: the credential spec with the failure switch on, and the Lean file with `≤` changed to
`<` in `bounded`.

## Method and limits

The specs are hand-written from the Swift. They model the steps named in their comments and nothing else, so "no violation" means no
violation among those steps. The Swift-to-TLA+ extractor that was built alongside (`modeler`, a separate repository, not part of ask)
was used only to survey ask: 504 types, 21 enum-valued members that are assigned, and no actors or global-actor types, so its
actor-reentrancy check has nothing to say about ask. It found no fault in ask.
