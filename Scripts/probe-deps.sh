#!/bin/sh
# Installs what the PTY probes need (Scripts/probe-requirements.txt) where they look for it by default, a cache that outlives /tmp
# (t246: a cleaned /tmp took pyte with it). Prints the directory. ASK_PYTE chooses another.
set -eu
here=$(cd "$(dirname "$0")" && pwd)
directory=$(python3 "$here/probe_pyte.py" --print-directory)
python3 -m pip install --quiet --disable-pip-version-check --upgrade --require-hashes --target "$directory" -r "$here/probe-requirements.txt"
echo "$directory"
