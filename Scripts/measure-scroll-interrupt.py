#!/usr/bin/env python3
"""Attempt n55/t236's input stall behind wheel reports, through the release binary and a headless PTY.

Scripts/measure-scroll-interrupt.py .build/release/ask [--events 2000] [--runs 6]
Uses measure-scroll-latency.py's PTY and fake provider; no pyte, real account or real terminal is needed.
A reverse-direction report and pasted draft follow each burst. The draft is erased, never submitted.
This is a reproduction attempt, not a precision benchmark: marker observation polls every 50 ms.
It cannot reproduce terminal-generated trackpad momentum or establish whether a gesture was stopped.
"""
import argparse
import importlib.util
import os
from pathlib import Path
import statistics
import tempfile
import time

HERE = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location('measure', HERE / 'measure-scroll-latency.py')
measure = importlib.util.module_from_spec(spec)
spec.loader.exec_module(measure)


def write_all(terminal, data):
    remaining = memoryview(data)
    while remaining:
        written = os.write(terminal.fd, remaining)
        if written <= 0:
            raise RuntimeError('The PTY stopped accepting input.')
        remaining = remaining[written:]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('binary', type=lambda value: str(Path(value).resolve()))
    parser.add_argument('--events', type=int, default=2000)
    parser.add_argument('--runs', type=int, default=6)
    options = parser.parse_args()
    if not 1 <= options.events <= 100_000 or not 1 <= options.runs <= 100:
        parser.error('Use 1..100000 events and 1..100 runs.')
    with tempfile.TemporaryDirectory(prefix='ask-scroll-interrupt-') as root:
        project = Path(root, 'project')
        project.mkdir()
        config = Path(root, 'config/ask')
        config.mkdir(parents=True)
        (config / 'config.json').write_text('{"ui":{"inputPrefix":"ask> ","shimmer":"off"}}')
        reply = '\n'.join(f'row {n} of an answer' for n in range(4000)) + '\nLONG DONE'
        server = measure.agent.Server([measure.agent.turn([('text', reply)], 'end_turn')])
        terminal = None
        try:
            env = measure.agent.environment(root + '/state', server.url, config=str(config.parent))
            env.update(TERM='xterm-256color', TERM_PROGRAM='kitty')
            terminal = measure.Pty(options.binary, str(project), env)
            terminal.until('ask>', seconds=120)
            terminal.send(b'go\r')
            terminal.until('LONG DONE', seconds=120)
            milliseconds = []
            for run in range(options.runs):
                marker = f'INTERRUPT_{run:03d}_{measure.MARK}_READY'
                button = 64 if run % 2 == 0 else 65
                opposite = 65 if button == 64 else 64
                data = f'\x1b[<{button};40;10M'.encode() * options.events
                data += f'\x1b[<{opposite};40;10M\x1b[200~{marker}\x1b[201~'.encode()
                sent = time.monotonic()
                write_all(terminal, data)
                terminal.until(marker, seconds=15)
                milliseconds.append((time.monotonic() - sent) * 1000)
                terminal.send(b'\x15')
            print(f'{options.events} wheel reports + reverse + draft, observed latency ms: '
                  + ', '.join(f'{value:.1f}' for value in milliseconds))
            print(f'median={statistics.median(milliseconds):.1f} ms; '
                  f'range={min(milliseconds):.1f}..{max(milliseconds):.1f} ms')
            print('Observation polls every 50 ms; no real-terminal gesture or momentum was tested.')
        finally:
            if terminal:
                terminal.close()
            server.httpd.shutdown()
            server.httpd.server_close()


if __name__ == '__main__':
    main()
