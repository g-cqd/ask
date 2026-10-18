#!/bin/bash
# Run the cell-pixel probe inside each real terminal, then print the results side by side.
#
# Each terminal is launched as `-e /bin/sh -c <probe>` so no shell configuration — no starship, no
# fish, no prompt — can influence what the terminal reports. The probe writes only to a file; this
# script is the only thing that reads those files, which keeps "what the terminal said about itself"
# separate from "what we concluded".
#
# This is roadmap entry 0014. The numbers it produces are the precondition for 0013 (adopting the
# render pipeline) and 0003 (active capability detection): no environment variable carries a cell
# size, so `supportsPixelChrome` cannot be satisfied by the env-var guess that 0003 replaces.
set -u

HERE=$(cd -- "$(dirname -- "$0")" && pwd)
P="$HERE/verify-cell-pixels.py"
OUT=${OUT:-/tmp/ask-cell-probe}
mkdir -p "$OUT"
rm -f "$OUT"/*.txt

wait_report() { # name, seconds
  local n=$1 limit=${2:-40}
  for _ in $(seq 1 "$limit"); do [ -s "$OUT/$n.txt" ] && return 0; sleep 0.5; done
  return 1
}

launch() {
  case $1 in
    kitty) kitty --config NONE -e /bin/sh -c "python3 $P $OUT/$1.txt; sleep 240" >/dev/null 2>&1 & ;;
    ghostty) /Applications/Ghostty.app/Contents/MacOS/ghostty \
                 -e /bin/sh -c "python3 $P $OUT/$1.txt; sleep 240" >/dev/null 2>&1 & ;;
    wezterm) wezterm start -- /bin/sh -c "python3 $P $OUT/$1.txt; sleep 240" >/dev/null 2>&1 & ;;
    terminal)
      # Written to a file and run by path. Nesting shell quoting inside an AppleScript string
      # inside a case statement is how the equivalent TerminalKit script silently stopped
      # launching, so it is kept out of the case body entirely.
      printf '#!/bin/sh\npython3 %s %s\nsleep 240\n' "$P" "$OUT/terminal.txt" > "$OUT/run-terminal.sh"
      chmod +x "$OUT/run-terminal.sh"
      osascript -e 'tell application "Terminal" to activate' >/dev/null 2>&1
      osascript -e "tell application \"Terminal\" to do script \"/bin/sh $OUT/run-terminal.sh\"" >/dev/null 2>&1 &
      ;;
    *) echo "unknown terminal: $1" >&2; return 2 ;;
  esac
}

TERMINALS=${TERMINALS:-"kitty ghostty wezterm terminal"}

echo "=== launching probes ==="
for t in $TERMINALS; do
  launch "$t" && echo "  launched $t" || echo "  SKIPPED $t (not launchable)"
done
for t in $TERMINALS; do
  wait_report "$t" 60 && echo "  $t reported" || echo "  $t DID NOT REPORT"
done

echo
echo "=== cell pixels, per terminal ==="
printf "%-12s %8s %8s %10s %10s %8s  %s\n" \
  TERMINAL "pxW" "pxH" "cellW" "cellH" "DRAWABLE" "VERDICT"
for t in $TERMINALS; do
  f="$OUT/$t.txt"
  if [ -s "$f" ]; then
    pxw=$(grep -m1 'pixelWidth' "$f" | grep -o '[0-9]\+' || echo "?")
    pxh=$(grep -m1 'pixelHeight' "$f" | grep -o '[0-9]\+' || echo "?")
    cw=$(grep -m1 'cell width' "$f" | grep -o '[0-9]\+' || echo "?")
    ch=$(grep -m1 'cell height' "$f" | grep -o '[0-9]\+' || echo "?")
    dr=$(grep -m1 '^- drawable' "$f" | awk '{print $3}' || echo "?")
    vd=$(grep -m1 -A1 '^## Verdict' "$f" | grep -o 'PIXELS\|NO_PIXELS\|NO_TTY' | head -1 || echo "?")
    printf "%-12s %8s %8s %10s %10s %8s  %s\n" "$t" "$pxw" "$pxh" "$cw" "$ch" "$dr" "${vd:-?}"
  else
    printf "%-12s %8s %8s %10s %10s %8s  %s\n" "$t" "-" "-" "-" "-" "-" "(no report)"
  fi
done

echo
echo "=== env-var guess vs measured pixels ==="
echo "TerminalKit reads KITTY_WINDOW_ID / TERM_PROGRAM / TERM. Where a terminal"
echo "reports NO_PIXELS the guess was right by luck; where it reports PIXELS but"
echo "the guess was false, roadmap 0003 has its evidence."
for t in $TERMINALS; do
  f="$OUT/$t.txt"
  [ -s "$f" ] || continue
  g=$(grep -m1 'guessed supportsKittyGraphics' "$f" | awk '{print $NF}')
  d=$(grep -m1 'measured cell size available' "$f" | awk '{print $NF}')
  printf "  %-12s guess=%-6s measured=%-6s %s\n" "$t" "$g" "$d" \
    "$( [ "$g" != "$d" ] && echo '<-- DISAGREE' || echo '' )"
done

echo
echo "Reports in $OUT"
echo
echo "Chrome byte costs in those reports are ESTIMATES from the encoder shape."
echo "The budget impact is measured separately: python3 Scripts/measure-budgets.py .build/release/ask 12"