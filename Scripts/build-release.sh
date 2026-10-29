#!/bin/sh
# Builds ask for release and signs it (Scripts/sign.sh), so the executable /reload switches to is already signed.
set -eu
cd "$(dirname "$0")/.."
swift build -c release "$@"
sh Scripts/sign.sh .build/release/ask
