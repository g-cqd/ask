#!/usr/bin/env python3
"""Measure the real bounded reply-path cache and uncached safe walk against fileExists (roadmap 0215).

Compiles the actual production Swift sources with -O (only the module import is removed to compile the subset together).
Nine interleaved samples, 1,000 checks each. Files are disposable, no terminal or provider is needed.
"""
from pathlib import Path
import statistics
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parent.parent
HARNESS = r'''
internal import Foundation
@main struct Measure {
    static func main() {
        let mode = CommandLine.arguments[1]
        let workspace = CommandLine.arguments[2]
        let checker = ReplyPathExistence()
        var count = 0
        let elapsed = ContinuousClock().measure {
            for _ in 0 ..< 1_000 {
                let found: Bool
                if mode == "old" {
                    found = FileManager.default.fileExists(atPath: workspace + "/a.txt")
                } else {
                    let reader = mode == "cold" ? ReplyPathExistence() : checker
                    found = reader.exists(workspace + "/a.txt", in: workspace, policy: .unrestricted)
                }
                if found { count += 1 }
            }
        }
        guard count == 1_000 else { fatalError("missing file") }
        let parts = elapsed.components
        print(Double(parts.seconds) * 1e9 + Double(parts.attoseconds) / 1e9)
    }
}
'''


def main():
    with tempfile.TemporaryDirectory(prefix='reply-path-cost-') as directory:
        work = Path(directory)
        sources = []
        for relative in ['Sources/AskTools/ReplyPathExistence.swift', *[
            f'Sources/AskAgentCore/Sandbox/{name}.swift' for name in
            ['SandboxPolicy', 'SandboxRule', 'SandboxCapability', 'SandboxDecision', 'PathScope', 'CanonicalPath']
        ]]:
            source = work / Path(relative).name
            source.write_text((ROOT / relative).read_text().replace('public import AskAgentCore\n', ''))
            sources.append(str(source))
        harness = work / 'Main.swift'
        harness.write_text(HARNESS)
        binary = work / 'measure'
        subprocess.run(['swiftc', '-O', '-enable-upcoming-feature', 'InternalImportsByDefault',
                        *sources, str(harness), '-o', str(binary)], check=True)
        (work / 'a.txt').write_text('a')
        samples = {mode: [] for mode in ['old', 'cold', 'cached']}
        for run in range(9):
            order = list(samples) if run % 2 == 0 else list(reversed(samples))
            for mode in order:
                nanos = float(subprocess.check_output([str(binary), mode, str(work)], text=True))
                samples[mode].append(nanos / 1_000_000)
        for mode, values in samples.items():
            print(f'{mode}: median {statistics.median(values):.3f} us/check; '
                  f'range {min(values):.3f}..{max(values):.3f}; 9 x 1000 checks')


if __name__ == '__main__':
    main()
