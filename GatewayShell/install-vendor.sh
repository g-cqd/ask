#!/bin/bash
# Copies @xterm/xterm and @xterm/addon-unicode-graphemes into GatewayShell/vendor/ before signing with `ask gateway sign-shell`.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

cd "$WORK"
npm init -y >/dev/null
npm install --silent @xterm/xterm@5 @xterm/addon-unicode-graphemes@0 >/dev/null

mkdir -p "$HERE/vendor"
cp node_modules/@xterm/xterm/css/xterm.css "$HERE/vendor/xterm.css"
npx --yes esbuild node_modules/@xterm/xterm/lib/xterm.mjs --bundle --format=esm --outfile="$HERE/vendor/xterm.mjs" >/dev/null
npx --yes esbuild node_modules/@xterm/addon-unicode-graphemes/lib/addon-unicode-graphemes.mjs --bundle --format=esm --outfile="$HERE/vendor/addon-unicode-graphemes.mjs" >/dev/null

echo "Installed xterm.js + @xterm/addon-unicode-graphemes into $HERE/vendor/. Next: ask gateway sign-shell --shell-dir '$HERE'"
