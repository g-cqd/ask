---
status: in-progress
blocked-by: []
date: 2026-10-28
---

# 0110 — API keys are kept in the system keychain by default

Owner wish (2026-10-28 19:22): instead of saving keys in files, use the system keychain by default; files stay possible as a config
setting.

## Done (2026-10-29, ADR-0133)

- Secrets only (tokens, client secret, keys) in one Keychain item per record; metadata stays in the file with a marker in place of each
  secret. Writes store and read back before the file changes; a failing Keychain leaves everything as it was.
- `credentials`: `auto` (Keychain for a signed build, file for an ad-hoc one, which never moves anything), `keychain`, `file`; own config
  only. Changing it moves what is stored, for ask's file and every named connection's.
- Tests: in-memory store for the file's logic (mutation: file written before the store, red), a throwaway keychain for the Keychain store,
  the auto rule (mutation red), and an end-to-end run of the release binary against a throwaway keychain (`ASK_KEYCHAIN_PATH`): keychain,
  file, keychain, auto unsigned both ways.

## Still owed

- A signing step with the personal Apple Development identity (`ASK_SIGNING_IDENTITY`), run after the build and before `/reload` switches;
  then the first signed run moves the real credentials into the login keychain, to be checked by hand.
- A locked keychain over SSH, checked for real (only the message is written).

## Investigation (2026-10-29)

**Inventory.** Every key and token goes through `CredentialFile` (`Sources/AskAI/Credentials`): one 0600 JSON document,
`~/.config/ask/credentials.json`, changed in one locked transaction (read, change one record, write by rename) shared by every ask
process, read without a lock. It holds the Claude, Codex, Copilot and Antigravity sign-ins (access and refresh tokens, refreshed often)
and API keys (`keys`). Named connections use their own files through the same type.

**Keychain behaviour, measured** in throwaway keychain files (`security create-keychain`), never the login keychain, with the UI turned
off so a prompt shows as a status:

| Writer and reader | Result |
|---|---|
| the same ad-hoc build | read, no prompt |
| a rebuilt ad-hoc binary (new code hash) | `-128`: would prompt, once per item, after every rebuild |
| both signed with the personal Apple Development identity (designated requirement on the certificate, not the hash) | read, no prompt across the rebuild |
| the data-protection keychain, either signing | `-34018`: needs the `keychain-access-groups` entitlement, which needs a provisioning profile |

So the Keychain is usable without constant prompts only for builds signed with a stable identity; ad-hoc builds (today's, rebuilt many
times a day through `/reload`) would prompt for every stored item after every build. Signing itself asks for the identity's private key
(the owner saw the prompt) unless `codesign` is allowed to use it.

**Design this points to.**

- One generic password item holding the whole document, so the existing transactions, lock and rename semantics stay, and one prompt at
  most is ever possible, not one per provider.
- Legacy (login) keychain, access bound to the binary's designated requirement; the data-protection keychain only with a provisioning
  profile later (distribution, 0070).
- `credentials.store`: `"auto"` (the Keychain when the running binary has a stable signature, else the file), `"keychain"`, `"file"`.
  Migration copies the file into the Keychain and removes the file only after reading it back; a locked or unavailable keychain (SSH,
  `security` errors) falls back to the file with a notice, never silently.
- Builds signed with the personal identity, after the build and before `/reload` switches (the self-check runs the signed binary).
- Tests against a throwaway keychain file, never the login keychain.

**Waiting for the owner:** whether ask's builds are signed with the personal Apple Development identity (which needs `codesign` allowed
to use its key once), or the Keychain stays for signed builds only.
