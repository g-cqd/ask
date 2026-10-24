---
status: in-progress
blocked-by: []
date: 2026-10-20
---

# 0046 — Named connections are provider instances, not provider implementations

The user approved multiple registrations/accounts of the same provider, and asked for a refined design before the
storage and CLI become fixed. This is the proposed direction, not a claim that the commands below already exist.
Credential transactions (0045, ADR-0039) are done. Still owed here from it: keep top-level records this version does not know
when saving, and a refresh lock per connection. Catalog discovery in 0038 is the first independent
slice and must already reject cache reuse across accounts/endpoints.

## Three identities, one selected destination

- **Provider kind** owns a protocol, auth flow and endpoint rules: Codex, Anthropic, or OpenAI-compatible. It is code,
  not a singleton account or a dynamically loaded provider framework.
- **Connection** is one registered destination: stable internal id, editable local name, provider kind, endpoint or
  region when applicable, and a credential reference. Two connections may use the same kind. The human name is not
  a filename, credential key, account id or session identity.
- **Model** has the server's raw id and reported capabilities/limits within that connection. Multiple models are normal.
  Local aliases and overrides are the separate, independently completable work in 0047.

`--provider` continues to select a destination, for compatibility with today's configured provider names. Help text
will call it a connection. Do not add competing `--account`, `--profile`, `--connection` and `--provider` selectors.
A connection already identifies the account; extra selectors would create combinations that disagree.

## Proposed commands

```sh
ask login codex --name personal
ask login codex --name work
ask connections
ask models work
ask --provider work --model <server-id>
ask --provider work --print 'Reply briefly.'
ask logout work
ask connections rename work employer
ask connections remove employer
```

A first login without `--name` preserves today's default provider connection. Reauthentication cannot replace a
connection of another provider kind. If the returned remote account differs from the one bound to an existing
connection, ask for explicit confirmation at a terminal, or a deliberately named replacement flag in a script.
The browser's account chooser and any force-account OAuth parameters must be probed, not inferred from their names.

`logout` removes authentication, not the connection or its model registrations. `remove` is the distinct destructive
operation. `connections` lists nonsecret names/kinds, configured/default status and whether credentials are present;
it must not claim that a stored token is accepted by a server. A future `--json` view must never print credentials.

## Reviewed invariants

1. **No silent switching.** A rate limit, authentication error, quota problem or unavailable model never sends the
   prompt through another account or endpoint. Automatic failover/load balancing is explicitly out of scope.
2. **Names do not shadow authority.** Reject duplicate or ambiguous names across configured endpoints, built-ins,
   presets and named registrations, rather than resolving a collision by surprising precedence. Existing names keep
   working. Normalize names once; case rules and accepted characters need explicit tests before landing.
3. **Configuration is not authentication.** Connection metadata/models and secret material are separate logical
   records; references use stable ids. A project configuration can select a trusted connection but cannot register,
   replace, export or reveal credentials. No API keys on command-line arguments; use the established environment or
   a deliberate stdin/terminal path for key registration.
4. **Endpoint binding.** Changing an authority, region or provider kind does not silently send its old credentials to
   the new destination. Preserve ADR-0024's transport policy. Environment overrides participate in the effective
   endpoint identity, including the catalog cache key.
5. **Account-scoped discovery.** Key catalogs by stable connection id, remote account identity and effective catalog
   endpoint/schema. Renaming does not invalidate an otherwise valid catalog; reauthenticating as another account
   does. Store only model descriptors, never the catalog's instructions, tokens or other account data.
6. **Selection is reproducible.** Explicit model flag, configuration, connection default, then the fresh live catalog's
   recommended ordering. Show the resolved connection/model and why a default was selected. A stale/failed catalog
   never causes a guessed static fallback; explicit raw ids remain available.
7. **Sessions bind destinations.** Record the stable connection id and resolved raw model id, never a token or email.
   Resume uses the recorded connection, not today's global default. An explicit user override may change destination
   and is reported before history is sent. Rename retains the binding; missing/deleted connections require an explicit
   choice. Legacy sessions without a binding must not acquire a different account silently.
8. **Migration is additive.** Old default credentials/settings continue to load with no rewrite on read and no need to
   sign in again. New writes retain unrelated records. No destructive whole-file migration or double-spending copied
   refresh tokens. Define compatibility with older ask binaries before changing the credential envelope.
9. **Secrets stay local.** Credentials stay in ask's owner-only store, behind the existing sandbox boundary. No reuse of
   another CLI's rotating refresh token. Cache/report errors must not echo server bodies or credential values.

## Review outcomes and alternatives

- Rejected one provider object per account: it confuses reusable transport behavior with a user's registration.
- Rejected a second account selector: the named connection already resolves that ambiguity.
- Rejected deriving persistent ids from names: rename would otherwise become a credential/session migration.
- Rejected implicit alias-to-other-connection fallback: it could move transcript data or spending between accounts.
- Rejected auto-selecting the first stored account: registration order is not consent or a stable default.
- Kept exact storage placement open until 0045: two config/secret files cannot simply be assumed to commit atomically;
  embedding secret-free metadata in a credential envelope also has migration/older-writer implications to probe.
- Deferred generic provider plugins, quota scheduling, account pools and TUI pickers. First make two explicit named
  connections work correctly through the CLI and existing provider seam.

## Done (diary 44, ADR-0048)

Registration, per-connection credentials, locks and catalogs; `ask login codex|claude --name`, `ask connections` with `rename` and
`remove`, `ask models NAME`, `ask logout NAME`; stable ids with an authorization identity; reserved names; sessions that record
their destination and resume by it (format 2, with version 1 still read); unknown credential records preserved; a newer
registration schema refused. Verified offline on the release binary with synthetic credentials, and against a real credentials
file left unchanged.

## Still owed

- A named Claude sign-in, and **probing the OAuth account chooser**, which this entry required. A real browser sign-in with
  `--name` is done (diary 44, probes 136-139) but the user has one account, so it registered *the same* ChatGPT account as the
  default, as a separate grant: the chooser question is still open, and a second sign-in does not by itself give a second
  account. Consider warning when a new sign-in lands on an account another connection already holds.
- ~~Whether Claude's refresh response identifies the account~~ **Yes**: the address and organisation, probed live (ADR-0073); a named
  connection is now held to its account on refresh.
- A `--json` listing, an interface picker, and named connections for key-based providers: deliberately not built.

## Acceptance

Two accounts of one provider can coexist, list their own models, run explicitly, refresh without crossing credentials,
log out independently and survive a rename/resume. Tests prove collision refusal, no automatic failover and
configuration precedence, including a project file attempting to replace credential metadata. A release CLI probe
covers registration, list, selection and logout against an injected fake account service before a real-account check.
Cold startup and cache-hit paths get interleaved before/after measurements; ordinary startup must not fetch every
registered connection's models. Commands in user guidance are fish-safe or avoid shell-specific assignments.
