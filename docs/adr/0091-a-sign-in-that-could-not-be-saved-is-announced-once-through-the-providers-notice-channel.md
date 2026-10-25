---
status: accepted
date: 2026-10-25
---

# 0091 — A sign-in that could not be saved is announced once, through the provider's notice channel

## Context

ADR-0082 made a refresh the server accepted survive a failed save: the rotated pair is kept in memory and the request goes ahead. It
recorded what that does not do: the person is not told. If ask is closed before a later request saves the pair, the next run is signed
out with nothing to say why, and "run `ask login`" reads as ask forgetting them. `ModelEvent.notice` was designed for exactly this ("something
the provider layer did that the person should be told") and is mapped to a transcript notice in the screen and to stderr in `-p`, but
nothing emitted it, and the assembler threw `notStarted` for any event before `messageStarted`: a notice sent first would have ended
the run.

## Decision

1. **A notice is not part of a response, wherever it comes.** The assembler ignores `.notice` before the response started, in the middle
   of it, and after it.
2. **`RotationNotice` decides when to speak.** Once when a rotation is first found unsaved, naming the provider and the reason the file
   gave; silent while the same failure goes on; armed again once a save worked, so a second failure is announced too.
   The text says what happens next: ask keeps the sign-in in memory and tries again on the next request, and if the person quits
   first they will need to sign in again.
3. **`NoticingProvider` delivers it.** A wrapper over any provider, in `AskAgentCore`: it asks for the notice once per request, after
   the first event (the request is under way and the credentials were used), or at the end of a stream that had none, so a request that
   fails at once still says it, and then still fails. It changes nothing the model sends or receives.
4. **The accessors say why.** `unsavedReason` on `ClaudeAccess` and `CodexAccess` is what the file said when it could not take the pair;
   nil once it is saved.
5. **Claude and Codex are wrapped in the composition root.** Other providers have no rotating sign-in and are not.

## What this does not do

It does not write the pair anywhere else or hold the refresh lock (ADR-0082 declined both). It does not tell a second ask process; a
second process sees the spent token and is refused, as the addendum to ADR-0082 records. It is not a channel for the model-list
lookups of roadmap 0053, whose notices are a different path.

## Probes

Unit tests for the assembler, the notice's states, the wrapper (order, once per request, the empty stream, the failing stream, an
untouched stream) and the loop running a turn that carries a notice; fourteen compiling mutants, all caught. Not probed with the real
binary: the token endpoint is a constant by design, so no run can be made to rotate a token and fail to save it. The composition root has
no tests (roadmap 0028), so the wiring of the two wrappers is checked only by building and by the existing probes.
