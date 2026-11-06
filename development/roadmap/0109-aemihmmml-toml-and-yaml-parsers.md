---
status: done
blocked-by: []
date: 2026-10-28
---

# 0109 — AemiHMMML: high-performance TOML and YAML

Owner wish (2026-10-28 19:10): alongside AemiJSON, AemiProtobuf and AemiRegex, a high-performance package named AemiHMMML ("aemi how
much more markup languages") for TOML and YAML. Investigate other formats worth including, and replace the parsers this repo wrote itself.

## Done (2026-11-06)

AemiHMMML (g-cqd/AemiHMMML) exists: TOML 1.0 and 1.1 (toml-test 100 %, a canonical writer, Codable), YAML 1.2.2 events and
documents (all 402 yaml-test-suite cases, every error case refused, the suite's JSON matched), a recovering policy for both, and one
front matter locator. Its plan (`docs/research/plan-2026-11-05.md`) answered this entry's questions and records the benchmarks. ask's
definition reader now uses it (ADR-0147), and its own parsers are deleted. The other candidate formats (INI, `.env`, plist) are
AemiHMMML's later phases; 0130 needs only what is here to start.

## What it said was owed

- Inventory the TOML and YAML parsing in ask today: where it is, what it supports, and who calls it.
- Choose the scope: full TOML 1.0, and which YAML subset (1.2 core schema, front matter only?), with conformance suites as tests.
- Benchmarks against the current parsers and a known reference, like the other Aemi packages.
- Candidates to investigate for inclusion: INI, `.env`, plist, front matter as a format.
- Replace the in-repo parsers once the package passes its conformance tests.

## Open questions

- Which YAML subset is enough, given that full YAML is large and few uses here need anchors or tags?
