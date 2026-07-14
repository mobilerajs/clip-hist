#!/bin/bash
# Ignored-apps + secret-detection watcher test. Touches the LIVE clipboard
# (saved/restored) and briefly activates Finder (focus steal ~2s, restored).
set -u
REPO="$(cd "$(dirname "$0")/.." && pwd)"
CLIPHIST_DATA_DIR="$(mktemp -d)"
export CLIPHIST_DATA_DIR
H="$CLIPHIST_DATA_DIR/history.jsonl"
BIN="$CLIPHIST_DATA_DIR/watcher"
fail=0
swiftc -O "$REPO/watcher/main.swift" -o "$BIN" || { echo "FAIL: compile"; exit 1; }

printf '{"ignored_apps": ["com.apple.finder"], "skip_secrets": "on"}\n' > "$CLIPHIST_DATA_DIR/config.json"
prev_bundle=$(lsappinfo info -only bundleid "$(lsappinfo front)" | sed 's/.*=//; s/"//g')
saved="$(pbpaste 2>/dev/null || true)"

"$BIN" & WPID=$!
sleep 1
printf 'ghp_abcdefghijklmnopqrstuvwxyz123456' | pbcopy; sleep 1        # secret: skipped
printf 'plain harmless text' | pbcopy; sleep 1                          # recorded
printf 'OPENAI_API_KEY=sk-abcdefghijklmnopqrstuvwxyz123456' | pbcopy; sleep 1   # embedded secret: skipped
printf 'export GITHUB_TOKEN="ghp_999999nopqrstuvwxyzabcdefghijkl"' | pbcopy; sleep 1  # embedded secret: skipped
printf '{"token": "ghp_qrstuvwxyzabcdefghijklmnop111111"}' | pbcopy; sleep 1    # embedded secret: skipped
printf 'retention=8h is a setting' | pbcopy; sleep 1                    # assignment, no secret: recorded
open -a Finder; sleep 1
printf 'copied-while-finder-front' | pbcopy; sleep 1                    # ignored app: skipped
[[ -n "$prev_bundle" ]] && open -b "$prev_bundle" 2>/dev/null; sleep 1
printf '{"ignored_apps": [], "skip_secrets": "off"}\n' > "$CLIPHIST_DATA_DIR/config.json"
printf 'ghp_zyxwvutsrqponmlkjihgfedcba654321' | pbcopy; sleep 1         # secrets off: recorded
kill $WPID 2>/dev/null
printf '%s' "$saved" | pbcopy

grep -q 'ghp_abcdef' "$H" && { echo "FAIL: secret recorded"; fail=1; }
grep -q 'plain harmless text' "$H" || { echo "FAIL: normal copy missing"; fail=1; }
grep -q 'copied-while-finder-front' "$H" && { echo "FAIL: ignored app recorded"; fail=1; }
grep -q 'ghp_zyxwvu' "$H" || { echo "FAIL: secrets-off copy missing"; fail=1; }
grep -q 'sk-abcdefghijklmnopqrstuvwxyz123456' "$H" && { echo "FAIL: embedded OPENAI_API_KEY secret recorded"; fail=1; }
grep -q 'ghp_999999nopqrstuvwxyzabcdefghijkl' "$H" && { echo "FAIL: embedded GITHUB_TOKEN secret recorded"; fail=1; }
grep -q 'ghp_qrstuvwxyzabcdefghijklmnop111111' "$H" && { echo "FAIL: embedded JSON token secret recorded"; fail=1; }
grep -q 'retention=8h is a setting' "$H" || { echo "FAIL: assignment-form non-secret missing"; fail=1; }
[[ $fail == 0 ]] && echo "ok: watcher privacy filters"
exit $fail
