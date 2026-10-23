#!/usr/bin/env python3
"""Fixed-cohort, isolated PTY startup diagnostics. A sample ends at the first complete prompt frame.

Example: Scripts/measure-startup.py .build/release/ask --runs 40 --idle-seconds .35 --output /tmp/startup.json
Use --control PATH for binary pairs, or --idle-control-seconds 0 to compare launch cadence on one artifact.
Pairs alternate order. --traced requires the research patch's phase markers on the
primary binary. Child processes are deliberately killed after sampling: no prompt is submitted, no job starts,
and each PTY is discarded. Lifetime CPU is diagnostic, not an internal startup latency claim.
"""
import argparse
import fcntl
import hashlib
import json
import math
import os
from pathlib import Path
import pty
import re
import select
import signal
import statistics
import struct
import subprocess
import sys
import tempfile
import termios
import time

PROMPT, FRAME_END = b'ask>', b'\x1b[?2026l'
TRACE = re.compile(rb'TRACE ([a-z_.]+) ([0-9]+) ([0-9]+) ([0-9]+) ([0-9]+) ([0-9]+) ([0-9]+)')


def stats(values):
    if not values:
        return None
    ordered = sorted(values)
    rank = lambda p: ordered[max(0, math.ceil(len(ordered) * p) - 1)]
    return dict(p50=statistics.median(ordered), p25=rank(.25), p75=rank(.75), p95=rank(.95),
                minimum=ordered[0], maximum=ordered[-1])


def shipping_cohort(rows, changed=False, traced=False):
    return bool(rows) and not changed and not traced and all(not r['error'] and not r['phases'] for r in rows)


def core_class(cpu_number, efficiency_cpus):
    """`efficiency` when the sampled logical CPU is among the host's first `efficiency_cpus`, else `performance`.

    Host assumption, checked by hand on one Apple-silicon machine through IORegistry: logical CPUs
    0..efficiency-1 are the efficiency cores. Re-check it with `ioreg` before trusting it elsewhere."""
    return 'efficiency' if cpu_number < efficiency_cpus else 'performance'


def by_core(rows, efficiency_cpus):
    """Cold-frame statistics by the core the process was on at its first phase marker. Only rows that completed
    and carry the marker count; the totals show how many were left out, so nothing is dropped silently."""
    groups, left_out = {}, 0
    for row in rows:
        marker = next((m for m in row['phases'] if m['phase'] == 'arguments'), None)
        if row['error'] or marker is None or row['cold_ms'] is None:
            left_out += 1
            continue
        groups.setdefault(core_class(marker['cpu_number'], efficiency_cpus), []).append(row['cold_ms'])
    return dict(left_out=left_out, efficiency_cpus=efficiency_cpus,
                groups={k: dict(count=len(v), **stats(v)) for k, v in sorted(groups.items())})


def efficiency_cpu_count():
    """Logical CPUs in the efficiency level (`hw.perflevel1`), or 0 when the host has no such level."""
    out = subprocess.run(['/usr/sbin/sysctl', '-n', 'hw.perflevel1.logicalcpu'], capture_output=True, text=True)
    return int(out.stdout) if out.returncode == 0 and out.stdout.strip().isdigit() else 0


def phases(raw):
    names = ('wall_ns', 'cpu_us', 'cpu_number', 'requested_qos', 'task_priority', 'cpu_query_status')
    return [dict(phase=m[0].decode(), **dict(zip(names, map(int, m[1:])))) for m in TRACE.findall(raw)]


def sample(binary, directory, environment, timeout=10, arguments=()):
    start = time.monotonic_ns()
    pid, fd = pty.fork()
    if pid == 0:
        fcntl.ioctl(0, termios.TIOCSWINSZ, struct.pack('HHHH', 40, 120, 0, 0))
        os.chdir(directory)
        os.execve(binary, [binary, *arguments], environment)
    parent = time.monotonic_ns()
    raw, first, frame, error = bytearray(), None, None, None
    try:
        deadline = time.monotonic() + timeout
        while True:
            remaining = deadline - time.monotonic()
            if remaining <= 0 or not select.select([fd], [], [], max(0, remaining))[0]:
                error = 'deadline before a complete prompt frame'
                break
            try:
                chunk = os.read(fd, 65536)
            except OSError:
                chunk = b''
            if not chunk:
                error = 'process/PTY ended before a complete prompt frame'
                break
            now = time.monotonic_ns()
            if first is None:
                first = now
            raw.extend(chunk)
            if len(raw) > 128 * 1024:
                error = 'startup output exceeded 128 KiB'
                break
            at = raw.find(PROMPT)
            if at >= 0 and raw.find(FRAME_END, at) >= 0:
                frame = now
                break
    finally:
        # Only this unreaped child can own pid. Kill before closing the PTY, then reap it; never leave a zombie.
        try:
            os.kill(pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
        os.close(fd)
        _, status, usage = os.wait4(pid, 0)
    row = dict(fork_ms=(parent - start) / 1e6, cold_ms=None if frame is None else (frame - start) / 1e6,
               post_fork_ms=None if frame is None else (frame - parent) / 1e6,
               first_byte_ms=None if first is None else (first - start) / 1e6,
               lifetime_cpu_ms=(usage.ru_utime + usage.ru_stime) * 1000,
               exit_code=os.waitstatus_to_exitcode(status), phases=phases(raw), error=error,
               resource_counters=dict(minor_faults=usage.ru_minflt, major_faults=usage.ru_majflt,
                                      input_blocks=usage.ru_inblock, voluntary_switches=usage.ru_nvcsw,
                                      involuntary_switches=usage.ru_nivcsw))
    if b'TRACE_ERROR' in raw or any(m['cpu_query_status'] != 0 for m in row['phases']):
        row['error'] = 'phase probe reported a query error'
    if row['error']:
        row['output_tail'] = raw[-4096:].decode(errors='replace')
    return row


def isolated_environment(root):
    env = {k: v for k, v in os.environ.items()
           if not k.startswith(('ASK_', 'ANTHROPIC_', 'OPENAI_', 'CODEX_', 'XDG_'))}
    env.update(XDG_CONFIG_HOME=str(root / 'config'), XDG_STATE_HOME=str(root / 'state'),
               TERM='xterm-kitty', TERM_PROGRAM='kitty')
    return env


def fingerprint(path):
    value = path.stat()
    return value.st_dev, value.st_ino, value.st_size, value.st_mtime_ns


def host():
    result = dict(cpu_count=os.cpu_count(), load_average=os.getloadavg(), platform=sys.platform,
                  release=os.uname().release)
    if sys.platform == 'darwin':
        pressure = subprocess.run(['/usr/sbin/sysctl', '-n', 'kern.memorystatus_vm_pressure_level'],
                                  capture_output=True, text=True, timeout=5)
        result['memory_pressure'] = pressure.stdout.strip() if pressure.returncode == 0 else None
    return result


def save(path, result):
    path.parent.mkdir(parents=True, exist_ok=True)
    text = json.dumps(result, indent=2, allow_nan=False) + '\n'
    with os.fdopen(os.open(path, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600), 'w') as output:
        output.write(text)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('binary', type=Path)
    controls = parser.add_mutually_exclusive_group()
    controls.add_argument('--control', type=Path)
    controls.add_argument('--idle-control-seconds', type=float)
    parser.add_argument('--runs', type=int, default=20)
    parser.add_argument('--idle-seconds', type=float, default=.35)
    parser.add_argument('--directory', type=Path, default=Path.cwd())
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--traced', action='store_true')
    args = parser.parse_args()
    intervals = [args.idle_seconds] + ([] if args.idle_control_seconds is None else [args.idle_control_seconds])
    if args.runs < 1 or any(value < 0 or not math.isfinite(value) for value in intervals):
        parser.error('runs must be positive and idle intervals finite and nonnegative')
    programs = dict(candidate=args.binary.resolve())
    cadences = dict(candidate=args.idle_seconds)
    if args.control:
        programs['control'] = args.control.resolve()
        cadences['control'] = args.idle_seconds
    elif args.idle_control_seconds is not None:
        programs['control'] = args.binary.resolve()
        cadences['control'] = args.idle_control_seconds
    fingerprints = {name: fingerprint(path) for name, path in programs.items()}
    result = dict(method='startup-frame-v1', geometry=[40, 120], requested_per_binary=args.runs,
                  idle_seconds=cadences, directory=str(args.directory.resolve()),
                  host_before=host(), binaries={k: str(v) for k, v in programs.items()}, samples=[], complete=False)
    save(args.output, result)
    with tempfile.TemporaryDirectory(prefix='ask-startup-') as directory:
        env = isolated_environment(Path(directory))
        try:
            for index in range(args.runs):
                order = list(programs) if index % 2 == 0 else list(reversed(programs))
                for name in order:
                    if cadences[name]:
                        time.sleep(cadences[name])
                    row = sample(str(programs[name]), str(args.directory.resolve()), env)
                    if name == 'candidate' and args.traced and not row['error']:
                        if not any(m['phase'] == 'screen.before_ui' for m in row['phases']):
                            row['error'] = 'required phase markers missing'
                    row.update(binary=name, index=index)
                    result['samples'].append(row)
                    save(args.output, result)
        except KeyboardInterrupt:
            result['interrupted'] = True
            save(args.output, result)
            return 130
        result['host_after'] = host()
        result['artifact_changed'] = [k for k, p in programs.items() if fingerprint(p) != fingerprints[k]]
        result['sha256'] = {k: hashlib.sha256(p.read_bytes()).hexdigest() for k, p in programs.items()}
        # Read the limit only after sampling, so this extra launch cannot warm the first sample.
        report = subprocess.run([str(args.binary.resolve()), '--budgets'], env=env,
                                capture_output=True, text=True, timeout=30)
        try:
            limit = json.loads(report.stdout)['coldStartMilliseconds'] if report.returncode == 0 else None
        except (KeyError, TypeError, ValueError):
            limit = None
        if isinstance(limit, bool) or not isinstance(limit, (int, float)) or not math.isfinite(limit) or limit <= 0:
            limit = None
        result['cold_limit_ms'] = limit
        result['complete'] = True
        result['summaries'] = {}
        for name in programs:
            rows = [r for r in result['samples'] if r['binary'] == name]
            good = [r for r in rows if not r['error']]
            summary = dict(completed=len(good), failed=len(rows) - len(good))
            for field in ('cold_ms', 'post_fork_ms', 'fork_ms', 'lifetime_cpu_ms'):
                summary[field] = stats([r[field] for r in good])
            if any(r['phases'] for r in rows):
                summary['by_starting_core'] = by_core(rows, efficiency_cpu_count())
            result['summaries'][name] = summary
            print(name, json.dumps(summary, sort_keys=True))
        save(args.output, result)
        cold = result['summaries']['candidate']['cold_ms']
        valid = shipping_cohort(result['samples'], bool(result['artifact_changed']), args.traced) and limit is not None
        over = cold is not None and limit is not None and cold['p50'] > limit
        result['budget_eligible'] = valid
        result['within_budget'] = valid and not over and cold is not None
        save(args.output, result)
        print('OVER BUDGET' if over else 'not certified' if not valid else 'within median budget', limit)
        return 0 if result['within_budget'] else 1


if __name__ == '__main__':
    sys.exit(main())
