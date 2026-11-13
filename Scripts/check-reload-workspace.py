#!/usr/bin/env python3
"""Check the real Reexec in isolated child processes, without a provider, PTY, account or terminal (n64, roadmap 0218).

Compiles Sources/AskSession/Reexec.swift with swiftc -O. A stale cwd is reproduced by removing and recreating its directory, not a
volume unmount. Tests the exact production exec helper; the harness passes a saved environment as the composition root does.
"""
from pathlib import Path
import os
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parent.parent
HARNESS = r'''
internal import Darwin
internal import Foundation

@main struct ReloadWorkspaceCheck {
    static func main() {
        let args = CommandLine.arguments
        let workspace = args[1]
        let mode = args[2]
        guard chdir(workspace) == 0 else { exit(90) }
        if mode == "stale" || mode == "missing" {
            guard rmdir(workspace) == 0 else { exit(91) }
            if mode == "stale", mkdir(workspace, 0o700) != 0 { exit(92) }
        } else {
            guard chdir("/") == 0 else { exit(93) }
        }
        let environment = ["PATH": "/usr/bin:/bin", "PWD": "/wrong", "ASK_CWD_CHECK": "saved"]
        let result = Reexec.replaceProcess(
            with: "/bin/sh",
            arguments: ["/bin/sh", "-c", "printf '%s\\n' \"$PWD\"; /bin/pwd -P; printf '%s\\n' \"$ASK_CWD_CHECK\""],
            workingDirectory: mode == "empty" ? "" : mode == "relative" ? "." : workspace,
            environment: environment
        )
        print("REEXEC_FAILED=\(result)")
        exit(result == ENOENT || result == EINVAL ? 42 : 94)
    }
}
'''


def main():
    with tempfile.TemporaryDirectory(prefix='ask-reload-cwd-') as directory:
        root = Path(directory)
        harness = root / 'Main.swift'
        harness.write_text(HARNESS)
        binary = root / 'check'
        subprocess.run(['swiftc', '-O', '-enable-upcoming-feature', 'InternalImportsByDefault',
                        str(ROOT / 'Sources/AskSession/Reexec.swift'), str(harness), '-o', str(binary)], check=True)
        for mode in ['ordinary', 'stale', 'missing', 'empty', 'relative']:
            workspace = root / f'{mode} project with spaces'
            workspace.mkdir()
            result = subprocess.run([str(binary), str(workspace), mode], text=True, capture_output=True)
            if mode in ['missing', 'empty', 'relative']:
                assert result.returncode == 42 and 'REEXEC_FAILED=' in result.stdout, (mode, result)
            else:
                expected = os.path.realpath(workspace)
                assert result.returncode == 0, (mode, result)
                assert result.stdout.splitlines() == [str(workspace), expected, 'saved'], (mode, result.stdout, result.stderr)
            print(f'PASS reload workspace: {mode}')


if __name__ == '__main__':
    main()
