#!/bin/sh
set -u
T=$(mktemp -d); H="$T/home"; mkdir -p "$H/.config/ask"; echo ORIGINAL > "$H/.config/ask/config.json"
HR=$(cd "$H" && pwd -P)
base='(version 1)(allow default)
(deny file-write* (subpath (param "ASK")))'
guard='(deny file-write-unlink (literal (param "PARENT")))'
attack() { # rename the parent away, edit the moved copy, rename back
  sandbox-exec -D ASK="$HR/.config/ask" -D PARENT="$HR/.config" -p "$1" sh -c "mv $HR/.config $HR/.config-away && echo TAMPERED > $HR/.config-away/ask/config.json && mv $HR/.config-away $HR/.config" 2>&1 | head -2
  printf '   config.json now says: %s\n' "$(cat $HR/.config/ask/config.json 2>/dev/null || echo '(missing)')"; [ -d "$HR/.config-away" ] && mv "$HR/.config-away" "$HR/.config" 2>/dev/null; echo ORIGINAL > "$HR/.config/ask/config.json"
}
echo "without the guard:"; attack "$base"
echo "with (deny file-write-unlink (literal PARENT)):"; attack "$base
$guard"
rm -rf "$T"
