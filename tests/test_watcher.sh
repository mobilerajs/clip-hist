#!/bin/bash
# WARNING: exercises the real system clipboard. Saves and restores current text clipboard.
set -u
REPO="$(cd "$(dirname "$0")/.." && pwd)"
CLIPHIST_DATA_DIR="$(mktemp -d)"
export CLIPHIST_DATA_DIR
H="$CLIPHIST_DATA_DIR/history.jsonl"
BIN="$CLIPHIST_DATA_DIR/watcher"
fail=0

swiftc -O "$REPO/watcher/main.swift" -o "$BIN" || { echo "FAIL: compile"; exit 1; }
swiftc -O "$REPO/tests/conceal.swift" -o "$CLIPHIST_DATA_DIR/conceal" || { echo "FAIL: compile conceal"; exit 1; }

# Seed an already-expired entry — watcher must prune it on first append
printf '{"ts": 1000, "app": "seed", "text": "ancient"}\n' > "$H"
# retention "0h" must be treated as invalid (fall back to default), not as
# "wipe everything" — the cutoff would otherwise sit at/after "now"
printf '{"retention": "0h"}\n' > "$CLIPHIST_DATA_DIR/config.json"

saved="$(pbpaste 2>/dev/null || true)"
"$BIN" & WPID=$!
sleep 1
printf 'clip-hist-test-one' | pbcopy; sleep 1
printf 'clip-hist-test-one' | pbcopy; sleep 1   # consecutive duplicate
printf 'line1\nline2' | pbcopy; sleep 1          # multi-line
printf '   ' | pbcopy; sleep 1                   # whitespace-only
"$CLIPHIST_DATA_DIR/conceal"; sleep 1            # password-manager style
touch "$CLIPHIST_DATA_DIR/paused"
printf 'while-paused' | pbcopy; sleep 1
rm -f "$CLIPHIST_DATA_DIR/paused"
printf 'clip-hist-test-one' | pbcopy; sleep 1    # re-copy older item: must move to top, not duplicate
printf 'retention-zero-h-recent' | pbcopy; sleep 1   # recent item; retention "0h" must not wipe it
printf 'Authorization: Bearer ghp_abcdefghijklmnopqrstuvwxyz1234567890' | pbcopy; sleep 1  # secret token inside header-style text
kill $WPID 2>/dev/null
printf '%s' "$saved" | pbcopy                    # restore user clipboard

c=$(grep -c 'clip-hist-test-one' "$H" || true)
[[ "$c" == "1" ]] || { echo "FAIL: dedupe (got $c)"; fail=1; }
grep -q 'line1\\nline2' "$H" || { echo "FAIL: multi-line missing"; fail=1; }
grep -q 'while-paused' "$H" && { echo "FAIL: recorded while paused"; fail=1; }
grep -q 'super-secret' "$H" && { echo "FAIL: recorded concealed item"; fail=1; }
grep -q 'ancient' "$H" && { echo "FAIL: expired seed not pruned"; fail=1; }
grep -q 'retention-zero-h-recent' "$H" || { echo "FAIL: retention 0h wiped a recent item"; fail=1; }
grep -q 'ghp_abcdefghijklmnopqrstuvwxyz1234567890' "$H" && { echo "FAIL: secret token inside header-style text was recorded"; fail=1; }
tail -1 "$H" | grep -q 'retention-zero-h-recent' || { echo "FAIL: re-copy did not move item to top"; fail=1; }
total=$(grep -c . "$H" || true)
[[ "$total" == "3" ]] || { echo "FAIL: expected 3 lines, got $total"; fail=1; }
[[ "$(stat -f %Lp "$H")" == "600" ]] || { echo "FAIL: perms $(stat -f %Lp "$H")"; fail=1; }

# Fresh (not pre-existing) data dir must be created 0700, not the OS/umask default.
# mktemp -d already yields 0700, so this needs a path the watcher creates itself.
FRESH_PARENT="$(mktemp -d)"
FRESH_DIR="$FRESH_PARENT/fresh-data-dir"
CLIPHIST_DATA_DIR="$FRESH_DIR" "$BIN" & FPID=$!
sleep 1
printf 'fresh-dir-probe' | pbcopy; sleep 1
kill $FPID 2>/dev/null
printf '%s' "$saved" | pbcopy
[[ "$(stat -f %Lp "$FRESH_DIR" 2>/dev/null)" == "700" ]] || { echo "FAIL: fresh data dir perms $(stat -f %Lp "$FRESH_DIR" 2>/dev/null)"; fail=1; }

[[ $fail == 0 ]] && echo "ok: watcher"
exit $fail
