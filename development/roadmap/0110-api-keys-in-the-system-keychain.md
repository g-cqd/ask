---
status: not-started
blocked-by: []
date: 2026-10-28
---

# 0110 — API keys are kept in the system keychain by default

Owner wish (2026-10-28 19:22): instead of saving keys in files, use the system keychain by default; files stay possible as a config
setting.

## Still owed

- Inventory where keys are written and read today (provider logins, `ask config`, environment).
- Keychain storage through the Security framework (system API, white paper rule), one generic password item per provider and account.
- A config setting that keeps the file store; migration of existing file keys, with the file removed only after the keychain write succeeds.
- Behaviour when the keychain is locked or unavailable (SSH sessions, Linux), and tests that do not touch the user's real keychain.
