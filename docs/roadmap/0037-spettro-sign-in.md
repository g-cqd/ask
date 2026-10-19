---
status: not-started
blocked-by: []
date: 2026-10-19
decision: ADR-0027
---

# 0037 — Spettro sign-in

Spettro speaks chat completions (probed: 401 in OpenAI's shape), so only its sign-in is missing: `POST /auth/initiate`,
a browser link, `GET /auth/poll/{session}` until a device key (10 minutes, 30 s a request), stored in ask's credential
file, plus its `/v1/models` catalog with `context_window`. `SPETTRO_API_URL` overrides the base. A live run needs the
user to sign in once.
