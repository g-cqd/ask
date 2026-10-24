---
status: accepted
date: 2026-10-24
---

# 0074 — The Antigravity sign-in confirms the secret first and keeps it with the credentials

## Context

ADR-0072 settled where the client secret comes from. Left open: how the sign-in uses it, where it lives between a sign-in and a
refresh, and what the sign-in is allowed to be before there is any inference. No account is needed to probe most of this (diary
2026-10-24-23); the one step that does (a real code for a real account) needs the owner's browser and has not run.

## The probes

- **Is the authorize request the shipped CLI's?** `agy` 1.4.6 prints it in a never-signed-in profile. ask's URL has the same nine
  parameters in the same order and the same values for all but the per-run challenge (43 characters) and state (22). **CONFIRMED.**
- **Does the exchange work as far as it can without an account?** A well-formed fake code, through ask's own request with a real
  verifier and the confirmed secret, gets Google's own HTTP 400 `invalid_grant`, reported as what to do. **CONFIRMED** to that point.
  A successful exchange was **not** observed.
- **Do the failure paths leave nothing behind?** A binary with no secret, a decoy Google rejects, an override that is not a file, a
  paste that is not a code, a refused code: each exits 77 and no credential file exists. **CONFIRMED** on the real binary.
- **Do the rules fail without their tests?** 30 deliberate faults in the sign-in layer (27 killed first time; three gaps closed and
  killed), 5 in the command wiring, all killed against baselines proven green (diary).

## Decision

1. **The authorize request is the shipped CLI's, byte for byte in shape**: endpoint, client id, hosted redirect, scopes in order,
   alphabetical parameters, spaces as `+`, PKCE S256, a 22-character random state.
2. **The secret is found and confirmed before any URL is shown**, so nobody signs in only to be refused afterwards. It is never
   printed; a failure says which step failed, never a candidate.
3. **What the user pastes is a code, or the redirect page's URL, or its query**, and nothing else: exactly the redirect's origin and
   path, no user information, no port, no `error`, exactly one code, at most one state and that state this sign-in's, a code of 10 to
   512 characters from Google's alphabet, the whole paste at most 4,096 characters. A bare code is accepted because PKCE binds it to
   this sign-in's verifier.
4. **The verified secret is stored with the credentials** (owner-only, in the credential file), so a refresh does not scan a 190 MB
   binary or send verification requests. A record an older build wrote has none. Rediscovering it when Google answers
   `invalid_client` belongs to the refresh that does not exist yet.
5. **Credentials are saved like every provider's**: one transaction under the shared lock, whole, beside the others, compare-and-
   replace for a refresh, unknown records kept verbatim. The renewal margin is 300 s; a refresh that returns no refresh token keeps
   the stored one; an account address from the ID token is display-only and only an ordinary address is shown.
6. **The default account only.** `ask login agy --name` is refused. A connection kind with no provider implementation behind it
   would be code nothing uses; it comes with inference (roadmap 0052).

## Consequences

- `ask login agy` works as far as a real code, and `ask logout agy` forgets the record. Nothing can use the credentials yet.
- The credential file now holds an application secret next to tokens. Google's own installed-application guidance, as the owner
  states it, treats it as not secret; the file is owner-only regardless.
- Google may or may not rotate refresh tokens; that is unknown until a real refresh runs, and decides whether Antigravity's
  refresh needs the lock Claude's and Codex's have (ADR-0073). Plan for the lock.
- Not covered: a real sign-in end to end, the refresh, onboarding, the model list, streaming, and the client-identity question.
