# Reproduce startup without confusing burst throughput with cold launch

This measures a fresh, isolated ask process externally over a 40×120 PTY. It is not an in-process stopwatch.
The 25 ms limit still comes from `ask --budgets`; it is never copied into the diagnostic tool.

## Shipping cohort

In your own clean worktree, build without testability immediately before copying the artifact:

```sh
swift build -c release --product ask
cp .build/release/ask /tmp/ask-shipping-startup
python3 Scripts/measure-startup.py /tmp/ask-shipping-startup \
  --runs 40 --idle-seconds .35 --output /tmp/startup-paced.json
```

The tool records **every** attempt and saves progress after each. An incomplete frame, failed trace query,
changed artifact or missing/invalid budget prevents certification. The cohort has a fixed requested size;
missing samples are not silently excluded to get a green median. All failures keep an output tail.

- `cold_ms`: before fork to the read completing the synchronized frame containing `ask>`.
- `post_fork_ms`: the legacy post-fork boundary, retained only for diagnostic comparison.
- `fork_ms`: parent-side process/PTY creation wall time, not application CPU.
- `first_byte_ms`: first observed output, not necessarily a rendered frame (trace output comes earlier).
- `lifetime_cpu_ms`: child CPU until deliberate termination, **not** an internally claimed startup latency.
- `resource_counters`: OS-reported faults, input blocks and context switches over that child lifetime.

Each child gets its size **before exec** and isolated configuration/state. Provider environment overrides are
removed. No prompt is submitted: after the first frame the probe deliberately SIGKILLs and reaps only its own
child, discarding that PTY. An exit code of -9 is expected here, not evidence of an application crash. This
probe does not test normal teardown, session durability or job cleanup; the executable suites do that.

The file records artifact paths, after-sampling SHA-256, fingerprints, host load/CPU count and macOS memory
pressure before and after the cohort. OS/file caches are **not cleared**. This is fresh-process startup, not
a claim about a physically cold disk. Before/after host snapshots do not establish the state at every instant.

Summaries use nearest-rank percentiles, including p95. With twelve observations, nearest-rank p95 is the
maximum. Always retain range and raw rows alongside medians; no best-sample or mean-only report.

## Same artifact, different cadence

```sh
python3 Scripts/measure-startup.py /tmp/ask-shipping-startup \
  --runs 40 --idle-seconds .35 --idle-control-seconds 0 \
  --output /tmp/startup-cadence.json
```

Both labels execute the **same artifact** and alternate order by pair. Only the preceding idle interval differs.
A zero interval is a **burst throughput** condition, not a substitute for an idle launch. A cadence effect may
interact with host conditions; one cohort does not prove a unique hardware/power-state cause.

For a code comparison, use `--control /tmp/ask-baseline-startup` instead. Both binaries then use the same
`--idle-seconds`. Code and cadence controls are mutually exclusive, so a supposedly one-variable experiment
cannot accidentally change both through these options.

## Phase overlay — never a shipping result

**`phases.patch` no longer applies** after the thinking-level work changed `ConfigurationSource.swift`; it is kept as a record of the
phase markers, and `core.patch` (starting core only) is the current, applying overlay. `phases.patch` is a small source overlay for `Sources/ask`: CLI-configuration entry, validation, run, configuration
layers/providers/model/policy, instruction discovery and the call into the screen. It writes to stderr:

```text
TRACE phase relative_wall_ns process_cpu_us sampled_cpu requested_qos task_priority cpu_query_status
```

Wall values are relative to the first probe call. CPU is cumulative process usage, including all threads.
The first CPU value includes work **before** that first call. No provider body, token or user prompt is printed.
The helper uses SDK-declared `getrusage`, `pthread_cpu_number_np` (macOS 11+) and `qos_class_self`; the floor is 26.

Apply only in a **separate disposable worktree**, never another agent's tree or the shipping source you measure:

```sh
repo=$(pwd)
git worktree add --detach ../ask-startup-trace HEAD
git -C ../ask-startup-trace apply --check "$repo/docs/research/startup/phases.patch"
git -C ../ask-startup-trace apply "$repo/docs/research/startup/phases.patch"
(cd ../ask-startup-trace && swift build -c release --product ask)
cp ../ask-startup-trace/.build/release/ask /tmp/ask-traced-startup
python3 Scripts/measure-startup.py /tmp/ask-traced-startup \
  --control /tmp/ask-shipping-startup --traced --runs 40 --idle-seconds .35 \
  --directory "$repo" --output /tmp/startup-phases.json
```

`--traced` requires the final phase marker. A traced cohort is diagnostic only and **cannot certify a shipping
budget**, even when its median is low; detected phase output also disqualifies an unflagged traced binary.
Measure overlay/control overhead on the same host instead of treating the trace as free. An application change
can make the overlay stop applying: inspect and regenerate it rather than forcing a stale patch.

CPU numbers are samples, not affinity: the SDK explicitly allows migration immediately after the query.
QoS is the **requested** class; it does not expose every effective override. A Task priority is not a CPU model.
If a CPU/cluster map is needed, inspect the current host rather than assuming its numbering:

```sh
ioreg -p IODeviceTree -r -n cpus -l | grep -E 'cpu[0-9]|"cluster-type"|"cpu-id"'
```

Remove the disposable trace tree afterward; do not publish its binary as shipping ask. The overlay is research
material, not code linked into any product or test target.

## Evidence and limits

Diaries 2026-10-22 (04) and (05) record the failed marker assumption, clock boundary, incomplete-cohort guard,
percentile correction, phase/cadence cohorts, controls and rejected entry/priority experiments. Application sources
were restored byte-for-byte; no runtime optimization or OS policy change was adopted.

**Efficiency-core starts are the strongest known factor, not a proven cause.** With `docs/research/startup/core.patch`
applied (it records the starting core; regenerate it if it stops applying) the tool reports cold time by starting
core. See diary 2026-10-22 (09): about 24 ms on an efficiency core, 12.5-13.7 ms on a performance core, share predicting
cohort medians. Always read a failing cohort's efficiency-core share before attributing it to the code.

**An earlier note stays true for the other factors:** The same artifact passed (13.98 ms) and failed (31-31.5 ms)
in cohorts at the same coarse memory-pressure level, and a generic fixed-work control shows only an 8-10% idle-gap
penalty. Do not attribute a slow cohort to cadence, load, QoS or core type from this tool alone; record the cohort,
keep its exit status, and compare against a control taken in the same period.
