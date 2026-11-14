---
status: accepted
date: 2026-11-14
---

# 0152 — What ask reads from the network before anyone asked is read by a child of itself

## Context

Since roadmap 0186 ask reads the workspace's GitHub repository when it starts: the open pull requests and issues for the `#`
picker, and the branch's pull request for the status bar. A process's first request makes the system load its network stack
(NetworkExtension, the TLS library, Skywalk: eight more mapped images), and it stays. Measured twice with the same binary: 16.7 MB
resident in a repository without a GitHub origin, 22.6 to 23.2 MB in one with.

An idle ask holds no network stack: model discovery waits for the first request (ADR-0116), MCP servers for the first message
(roadmap 0143). The GitHub read broke that without anyone deciding it should. Three ways were put to the owner (2026-11-14):
defer the read until `#` is typed and the first run ends; keep it and pay; or have a child process do it. The owner chose the child:
the pull request is in the status bar from the start, and the memory is not ask's.

## Decision

1. The read is one value, `ForgeSnapshot` (the open items as the picker lists them, the branch's pull request), and one hidden
   subcommand prints it as JSON: `ask forge DIRECTORY`.
2. The running ask starts its own executable (`BinaryIdentity.running()`) with that subcommand, reads what it printed, and the
   child ends. No child is started for a workspace whose `origin` is not on GitHub: git answers that, without the network.
3. The child's environment is the `PATH` and, when the person set one, `GITHUB_TOKEN`: in the environment, never among the
   arguments, which any process can read. It has twelve seconds. A child that fails, is late or prints something else is no list
   and no pull request, as a failed read was before.
4. `#123` in a message is still read in process: by then a request to the model is being made and the stack is needed anyway.

The rule for what comes next: a read ask makes by itself before the person's first message goes through a child, or waits.

## Consequences

- Idle in a GitHub repository, under the gate: 22.4 MiB before, 17.2 after. The stack's images are not mapped (660 against 668).
- A start costs one more process for a moment (ask's cold start, about 25 ms of CPU, then the wait on GitHub), off the screen's
  thread as the read already was.
- The child is the same binary, so the request goes through the same transport as before (no cache, cookie, stored credential or
  redirect: security audit 3). A binary replaced on disk while ask runs is the one started; if it does not know `forge` the read
  is nothing until `/reload`.
- The subcommand is not in the help. It prints what GitHub's public API says of the repository, nothing of the person's.
- Tests give `ForgeListing` a closure; the default starts the running executable, which under test is the test runner. No fixture
  has a GitHub origin, so none starts it.

## Probes

Diary 2026-11-14-05.
