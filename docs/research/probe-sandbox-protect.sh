#!/bin/sh
# Probes for ADR-0035: an allow-default profile with denials over ask's own directories and secret stores.
set -u
T=$(mktemp -d); H="$T/home"; mkdir -p "$H/.config/ask" "$H/.ssh" "$H/work" "$H/.aws"
echo '{}' > "$H/.config/ask/config.json"; echo 'sk-secret' > "$H/.config/ask/credentials.json"; echo KEY > "$H/.ssh/id_ed25519"; echo cfg > "$H/.ssh/config"
HR=$(cd "$H" && pwd -P)
run() { label="$1"; shift; out=$("$@" 2>&1); code=$?; printf '%-58s exit=%-3s %s\n' "$label" "$code" "$(echo "$out" | head -1 | cut -c1-58)"; }
P='(version 1)(allow default)
(deny file-write* (subpath (param "ASK")))
(deny file-read* (subpath (param "ASK")) (literal (param "KEY")))'
sb() { sandbox-exec -D ASK="$HR/.config/ask" -D KEY="$HR/.ssh/id_ed25519" -p "$P" "$@"; }
echo "--- canonical-path facts"
mkdir -p "$HR/Mixed"; run "realpath of a wrong-case alias (case-insensitive FS)" sh -c "python3 -c \"import os;print(os.path.realpath('$HR/.CONFIG/ASK'))\""
echo "--- writes into the protected directory"
run "create a file" sb sh -c "echo x > $HR/.config/ask/new"
run "overwrite config.json" sb sh -c "echo x > $HR/.config/ask/config.json"
run "wrong-case path" sb sh -c "echo x > $HR/.CONFIG/ASK/config.json"
run "rename a file in" sb sh -c "echo x > $HR/work/f && mv $HR/work/f $HR/.config/ask/f"
run "unlink config.json" sb sh -c "rm $HR/.config/ask/config.json"
run "rename the directory itself away" sb sh -c "mv $HR/.config/ask $HR/ask-moved"
run "hard link into it" sb sh -c "ln $HR/work/f $HR/.config/ask/l 2>/dev/null || (echo y > $HR/work/f2; ln $HR/work/f2 $HR/.config/ask/l)"
run "write through a symlink made elsewhere" sb sh -c "ln -s $HR/.config/ask/config.json $HR/work/link && echo x > $HR/work/link"
run "chmod config.json" sb sh -c "chmod 777 $HR/.config/ask/config.json"
run "touch config.json" sb sh -c "touch $HR/.config/ask/config.json"
echo "--- reads"
run "read credentials.json" sb cat "$HR/.config/ask/credentials.json"
run "read config.json (also denied: directory)" sb cat "$HR/.config/ask/config.json"
run "read the ssh private key" sb cat "$HR/.ssh/id_ed25519"
run "read ~/.ssh/config (allowed: ssh needs it)" sb cat "$HR/.ssh/config"
run "list the protected directory" sb ls "$HR/.config/ask"
echo "--- ordinary work still works"
run "write in the workspace" sb sh -c "echo ok > $HR/work/ok && cat $HR/work/ok"
run "git init and commit in the workspace" sb sh -c "cd $HR/work && git init -q && git -c user.email=a@b -c user.name=n commit -q --allow-empty -m x && git log --oneline | head -1"
echo "--- swift build under the profile"
mkdir -p "$HR/work/pkg/Sources/pkg"; cd "$HR/work/pkg"
printf '// swift-tools-version: 6.0\nimport PackageDescription\nlet package = Package(name: "pkg", targets: [.executableTarget(name: "pkg")])\n' > Package.swift
echo 'print("built")' > Sources/pkg/main.swift
run "swift build -c release (allow-default + denials)" sb swift build -c release --disable-sandbox
run "run the built binary" sb ./.build/release/pkg
rm -rf "$T"
