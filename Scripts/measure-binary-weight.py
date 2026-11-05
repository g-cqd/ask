#!/usr/bin/env python3
"""What a Mach-O executable weighs, and which module owns the code. Read-only: it copies the binary before stripping.

Example: Scripts/measure-binary-weight.py .build/release/ask
         Scripts/measure-binary-weight.py .build/release/ask --top 40 --json /tmp/weight.json

Reports, for one binary:
  - the file, each segment, and the code section;
  - the stripped size (`strip -S -x`, what swift-ci ships) and the symbol-table share of the file;
  - the dynamic libraries it loads (each one is a load command dyld resolves at launch);
  - the code size per Swift module, taken from mangled symbol names (the gap to the next symbol is the size).

Limits, so the numbers are not over-read:
  - Attribution follows the module in a symbol's mangled name. A generic specialisation of a standard-library type
    made inside your module is counted under "Swift (substitution)", not under your module.
  - A stripped binary keeps only global symbols, so attribution on one is partial; measure the unstripped build.
  - It measures size, not speed. A smaller binary is not faster: check the startup and benchmark scripts as well.
"""
import argparse
import collections
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile


def run(*command: str) -> str:
    return subprocess.run(command, capture_output=True, text=True, check=False).stdout


def segments(path: str) -> dict[str, int]:
    sizes: dict[str, int] = {}
    for line in run("size", "-m", path).splitlines():
        match = re.match(r"Segment (\S+): (\d+)", line)
        if match:
            sizes[match.group(1)] = int(match.group(2))
    return sizes


def text_bounds(path: str) -> tuple[int, int]:
    match = re.search(
        r"sectname __text\n\s+segname __TEXT\n\s+addr (0x[0-9a-f]+)\n\s+size (0x[0-9a-f]+)",
        run("otool", "-l", path),
    )
    if not match:
        sys.exit("no __TEXT,__text section: is this a Mach-O executable?")
    start = int(match.group(1), 16)
    return start, start + int(match.group(2), 16)


def module_of(symbol: str) -> str | None:
    name = symbol.lstrip("_")
    if not name.startswith("$s"):
        return None
    rest = name[2:]
    digits = re.match(r"\d+", rest)
    if not digits:
        return "Swift (substitution)"
    length = int(digits.group(0))
    start = len(digits.group(0))
    return rest[start : start + length]


def code_by_module(path: str) -> collections.Counter[str]:
    start, end = text_bounds(path)
    symbols: list[tuple[int, str]] = []
    for line in run("nm", "-n", path).splitlines():
        parts = line.split(None, 2)
        if len(parts) == 3 and parts[1] in ("t", "T"):
            address = int(parts[0], 16)
            if start <= address < end:
                symbols.append((address, parts[2]))
    totals: collections.Counter[str] = collections.Counter()
    for index, (address, name) in enumerate(symbols):
        upper = symbols[index + 1][0] if index + 1 < len(symbols) else end
        totals[module_of(name) or "C / other"] += upper - address
    return totals


def stripped_size(path: str) -> int:
    with tempfile.TemporaryDirectory() as directory:
        copy = os.path.join(directory, "binary")
        shutil.copyfile(path, copy)
        subprocess.run(["strip", "-S", "-x", copy], capture_output=True, check=False)
        return os.path.getsize(copy)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("binary")
    parser.add_argument("--top", type=int, default=25, help="modules to list (default 25)")
    parser.add_argument("--json", help="also write the figures to this file")
    arguments = parser.parse_args()
    path = arguments.binary
    if not os.path.isfile(path):
        sys.exit(f"{path}: no such file")

    size = os.path.getsize(path)
    parts = segments(path)
    stripped = stripped_size(path)
    libraries = [line.split()[0] for line in run("otool", "-L", path).splitlines()[1:] if line.strip()]
    modules = code_by_module(path)
    total = sum(modules.values()) or 1
    mib = 1048576

    print(f"{path}\n  file {size / mib:7.2f} MiB   stripped (strip -S -x) {stripped / mib:7.2f} MiB   "
          f"symbols and other link data {100 * (size - stripped) / size:4.1f}% of the file")
    for name in ("__TEXT", "__DATA_CONST", "__DATA", "__LINKEDIT"):
        if name in parts:
            print(f"  {name:13s} {parts[name] / mib:7.2f} MiB")
    system = [lib for lib in libraries if lib.startswith(("/System/", "/usr/lib/"))]
    print(f"  loads {len(libraries)} dynamic libraries ({len(system)} system); "
          f"frameworks: {', '.join(sorted({os.path.basename(l).split('.')[0] for l in libraries if '.framework/' in l}))}")
    print(f"\n  code by module (__text {total / mib:.2f} MiB)")
    for name, value in modules.most_common(arguments.top):
        print(f"  {value / 1024:9.0f} KiB {100 * value / total:5.1f}%  {name}")

    if arguments.json:
        with open(arguments.json, "w", encoding="utf-8") as handle:
            json.dump(
                {"binary": path, "bytes": size, "stripped_bytes": stripped, "segments": parts,
                 "libraries": libraries, "code_bytes_by_module": dict(modules.most_common())},
                handle, indent=2, sort_keys=True)


if __name__ == "__main__":
    main()
