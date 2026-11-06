# Roadmap audit, 2026-11-06

Every entry marked `in-progress`, read against its own "Still owed" or "Done when", with who the rest waits on. Done at the owner's
request ("take a look at the roadmap and all the remaining steps"), after the work of 2026-11-05.

## What changed in the entries

- 0195 (threads merge into their parent) was `not-started` with eleven "Done" sections: now `in-progress`, its four leftovers listed.
- 0066 (Mermaid in the transcript), 0186 (git integration: `#t3` and `#i2` are built) and 0071 (real use and a defect log: the owner's
  notes are the log) were `not-started` with work done: now `in-progress`.
- 0194, 0047 and 0151 listed as owed what has since been built (lanes, thread jobs, `/resume`, memory and caps; the `/model` picker;
  queued prompts as Markdown): struck through with where it was done.

No entry was marked `done`: none meets its "Done when" yet. Most are open on one last piece that is someone's in particular.

## Who each in-progress entry waits on

**ask's own work (mine to do):**

| Entry | Left |
|---|---|
| 0003 | Use `TerminalProbe` off the startup path; split cell pixels from the kitty graphics protocol; Esc latency (t24) |
| 0014 | The four budgets with chrome on and off, from one harness (t25) |
| 0033, 0192 | The hook host's items 2, 3, 5 and a reference hook; 0192's ADR and `run.stop` reference hook (t189, t50) |
| 0048 | A detail pane; `@` for sessions (behind 0115's transport ADR); trigger and ranking moved to TerminalKit |
| 0053 | Tests for reload forwarding and the deferred lookup's cancellation; the lookup's own notices shown |
| 0054 | Which of the 2,020 imports a bare launch reaches; a QoS intervention that reaches the process (now known: the app role, 8abd7e58) |
| 0074 | A test per width class, 20 to 200 columns; a PTY probe of the scroll case with tinted blocks; the ADR superseding 0015's lines |
| 0078 | Read windows as `[x:y]`; no input/output divider labels; payloads shown semantically |
| 0152 | Phase 4: fences in the draft, and a `bash` block's command |
| 0180 | An idea before the first prompt; `/idea` keeping its text's own spacing |
| 0194, 0195 | A thread's own task list and notes; the four leftovers of 0195 (t205) |
| 0114 | The MCP gaps daily use hits first; how ask's own development uses the servers |
| 0067 | Approval of what a server does beyond tools; prompts; sampling. OAuth: see the owner's list |

**The owner's (a look, an account, a key or a decision):**

| Entry | Waits on |
|---|---|
| 0034, 0038 | Keys for the remaining presets (each probed with its own key first) |
| 0040 | A direct OpenAI API account |
| 0046, 0052 | A second account (Claude's chooser; a second Google account for agy), and agy's terms (U22) |
| 0047 | Whether a model gone from the catalog is reported on use; aliases for the default connections are mine |
| 0051 | Agreeing the conventions ADR (step 3); tmux and ssh are unprobed |
| 0054 | How budgets treat the efficiency-core share |
| 0067 | OAuth: the registration strategy and the Client ID Metadata Document's hosting (t192) |
| 0071 | The ranking of the open notes |
| 0110, 0182 | The first real signing run, and "remember" in the real login keychain (t19, t20) |
| 0151, 0179, 0187 | A look in a real terminal: Markdown everywhere, `/tasks`, the shimmer (t16, t22) |

**The other session's (the family's Markdown and Mermaid work):** 0065's Aemi parts (the set scan), 0066 through 0198, 0139, 0196 to
0204, 0206. Their "Progress" sections are dated 2026-11-04 and -05; their gates are that session's.

**Research, low priority:** 0073 (Xcode's code model), 0115 (session takeover: other harnesses, the registry, what moves).

## Tasks that no longer say the truth (fixed with this audit)

t223 (subagents phases 2 to 5) is done (0063 is done); t37 named 0063 among what is open; t206 (the stuck scroll) is fixed in
8abd7e58, open only for the owner's look in kitty.

## Suggested order

1. The owner's decisions and looks, in one round of questions (the second table).
2. The owner's open notes, in the owner's order: t211, t201, t203, t204, t205 (with 0195's leftovers), t213, t214, t215, t217, t216,
   t209 with t222, t195, t196, t202.
3. Health as it breaks: CI and the Linux legs (t21), the probe sweep (t226), mutation testing (t184), budgets on a quiet machine (t14,
   t26).
4. Then the first table, entry by entry; 0078 and 0074 first, as they are the screen the owner looks at all day.
