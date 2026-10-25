#!/usr/bin/env python3
"""Fail when two documentation filenames use the same ADR, roadmap, or per-day diary number."""
import pathlib
import sys
sys.dont_write_bytecode = True

from record_numbers import disk_paths, duplicates

root = pathlib.Path(__file__).resolve().parent.parent
problems = duplicates(disk_paths(root))
for problem in problems:
    print(problem, file=sys.stderr)
sys.exit(1 if problems else 0)
