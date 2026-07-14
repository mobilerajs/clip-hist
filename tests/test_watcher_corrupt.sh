#!/bin/bash
# Corrupt-store test: watcher must NOT clobber an unreadable history file.
set -u
REPO="$(cd "$(dirname "$0")/.." && pwd)"
CLIPHIST_DATA_DIR="$(mktemp -d)"
export CLIPHIST_DATA_DIR
H="$CLIPHIST_DATA_DIR/history.jsonl"
BIN="$CLIPHIST_DATA_DIR/watcher"
fail=0

swiftc -O "$REPO/watcher/main.swift" -o "$BIN" || { echo "FAIL: compile"; exit 1; }

printf '\xff\xfe broken utf8 \xff\n' > "$H"
before="$(wc -c < "$H" | tr -d ' ')"

saved="$(pbpaste 2>/dev/null || true)"
"$BIN" & WPID=$!
sleep 1
printf 'corrupt-store-probe' | pbcopy; sleep 1
kill $WPID 2>/dev/null
printf '%s' "$saved" | pbcopy

after="$(wc -c < "$H" | tr -d ' ')"
[[ "$before" == "$after" ]] || { echo "FAIL: corrupt store was rewritten ($before -> $after bytes)"; fail=1; }
grep -q 'corrupt-store-probe' "$H" && { echo "FAIL: probe written into corrupt store"; fail=1; }
[[ $fail == 0 ]] && echo "ok: corrupt store preserved"
exit $fail
