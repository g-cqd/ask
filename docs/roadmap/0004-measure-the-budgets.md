---
status: not-started
blocked-by: ["0001", "0002", "0003"]
date: 2026-10-18
---

# 0004 — Measure the four budgets before optimising anything

Set the numbers `ask` will be held to: **cold start**, **idle memory**, **input delay**, and
**action-to-action delay**.

**Done when:** each budget has a measured baseline and a stated target, with units, produced by one
harness in release configuration; the harness is committed so later changes can be compared against
it; and each budget is guarded in CI against silent regression.

**Notes:** no number in this project is a guess. Until this entry lands, "ultra-performance" is an
unmeasured claim and nothing may be justified by it. Percentiles, not averages; median and spread,
never the best run. Interleave before-and-after runs so background load cancels out of the ratio.