#!/bin/bash
# Source-app attribution test: briefly activates Finder (focus steal ~2s),
# copies while Finder is frontmost, restores focus + clipboard.
set -u
REPO="$(cd "$(dirname "$0")/.." && pwd)"
CLIPHIST_DATA_DIR="$(mktemp -d)"
export CLIPHIST_DATA_DIR
BIN="$CLIPHIST_DATA_DIR/watcher"
fail=0

swiftc -O "$REPO/watcher/main.swift" -o "$BIN" || { echo "FAIL: compile"; exit 1; }

prev_bundle=$(lsappinfo info -only bundleid "$(lsappinfo front)" | sed 's/.*=//; s/"//g')
saved="$(pbpaste 2>/dev/null || true)"

"$BIN" & WPID=$!
sleep 1
open -a Finder
sleep 1
printf 'frontmost-app-probe' | pbcopy
sleep 1
kill $WPID 2>/dev/null
[[ -n "$prev_bundle" ]] && open -b "$prev_bundle" 2>/dev/null
printf '%s' "$saved" | pbcopy

app=$(/usr/bin/python3 -c "
import json
for l in open('$CLIPHIST_DATA_DIR/history.jsonl'):
    try: o = json.loads(l)
    except ValueError: continue
    if o.get('text') == 'frontmost-app-probe': print(o.get('app'))
")
if [[ "$app" == "com.apple.finder" ]]; then
  echo "ok: source app tracked (com.apple.finder)"
else
  echo "FAIL: expected com.apple.finder, got '$app'"
  fail=1
fi
exit $fail
