#!/bin/sh
# Integrate and gate a clean task worktree, fast-forward local main, and remove only that task. Never pushes.
set -eu
exec python3 "$(dirname "$0")/land.py" "$@"
