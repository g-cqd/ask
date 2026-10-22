---
name: Bug report
about: Something ask does wrong
labels: bug
---

**What happened** — a short description, and what you expected instead.

**How to reproduce** — the exact command (`ask -p "…"` or the screen), and the
smallest input that triggers it. A session file (path from `ask sessions`) is
often enough.

**Environment** — ask version (`ask --version`), macOS version, provider and
model, and whether the sandbox was modified (`--no-sandbox`, a `sandbox`
section in `config.json`).

**Output** — the screen, terminal or error text, in a code block.

Performance reports: give the command you ran and the numbers from
`Scripts/measure-budgets.py` or a measurement of your own — median and spread,
not the best run. A claim without a probe will be asked for one.
