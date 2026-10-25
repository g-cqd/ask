#!/bin/sh
# Repository-wide documentation numbers; --claim reserves with a compare-and-create git ref.
set -eu
exec python3 "$(dirname "$0")/next-number.py" "$@"
