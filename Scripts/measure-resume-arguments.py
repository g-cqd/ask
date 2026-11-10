#!/usr/bin/env python3
"""Interleave optimized shell-argument formatting before REF and in this tree (n54, t247).

Scripts/measure-resume-arguments.py [REF=HEAD] [RUNS=9]
Compiles the actual PathDisplay source with swiftc -O; no package rebuild or terminal is needed.
This is exit-formatting cost, not a startup or input-latency benchmark. Prints median and full range.
"""
from pathlib import Path
import statistics
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parent.parent
SOURCE = 'Sources/AskAgentCore/Session/PathDisplay.swift'
HARNESS = r'''
import Foundation
@main struct Measure {
    static func main() {
        let home = FileManager.default.currentDirectoryPath
        let arguments = ["--thinking", "high", "--no-sandbox", "--yes", "--selected-provider", "anthropic", "--selected-model", "claude-opus-5-5"]
        var checksum = 0
        let elapsed = ContinuousClock().measure {
            for _ in 0 ..< 1_000 {
                for argument in arguments { checksum += PathDisplay.shellArgument(argument, home: home).utf8.count }
            }
        }
        let parts = elapsed.components
        print(Double(parts.seconds) * 1e9 + Double(parts.attoseconds) / 1e9, checksum)
    }
}
'''


def main():
    ref = sys.argv[1] if len(sys.argv) > 1 else 'HEAD'
    runs = int(sys.argv[2]) if len(sys.argv) > 2 else 9
    if runs < 3:
        raise SystemExit('Use at least three paired runs.')
    with tempfile.TemporaryDirectory(prefix='ask-resume-measure-') as directory:
        work = Path(directory)
        harness = work / 'Measure.swift'
        harness.write_text(HARNESS)
        before = work / 'Before.swift'
        before.write_bytes(subprocess.check_output(['git', 'show', f'{ref}:{SOURCE}'], cwd=ROOT))
        for name, source in [('before', before), ('after', ROOT / SOURCE)]:
            subprocess.run(['swiftc', '-O', str(source), str(harness), '-o', str(work / name)], cwd=ROOT, check=True)
        samples = {'before': [], 'after': []}
        for run in range(runs):
            order = ('before', 'after') if run % 2 == 0 else ('after', 'before')
            for name in order:
                nanos, checksum = subprocess.check_output([str(work / name)], cwd=ROOT, text=True).split()
                if int(checksum) <= 0:
                    raise RuntimeError('The formatter returned no data.')
                samples[name].append(float(nanos) / 8_000 / 1_000)
        for name, values in samples.items():
            print(f'{name}: median {statistics.median(values):.3f} us/argument; '
                  f'range {min(values):.3f}..{max(values):.3f}; n={runs} x 8000')


if __name__ == '__main__':
    main()
