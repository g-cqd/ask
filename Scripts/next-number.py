#!/usr/bin/env python3
"""Print the next record number visible to this clone; --claim reserves it across its worktrees."""
import argparse
import datetime
import pathlib
import sys

sys.dont_write_bytecode = True

from record_numbers import git, next_number

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("kind", choices=["adr", "diary", "roadmap"])
parser.add_argument("--claim", action="store_true")
parser.add_argument("--date", default=datetime.date.today().isoformat(), type=lambda value: datetime.date.fromisoformat(value).isoformat())
args = parser.parse_args()
try:
    root = pathlib.Path(git(".", "rev-parse", "--show-toplevel").stdout.strip())
    print(next_number(root, args.kind, args.date if args.kind == "diary" else "", args.claim))
except (RuntimeError, OSError) as error:
    print("next-number: " + str(error), file=sys.stderr)
    sys.exit(1)
