#!/bin/bash
set -u
CLI="$(cd "$(dirname "$0")/.." && pwd)/bin/clip-hist"
fail=0
t() { if [[ "$2" == "$3" ]]; then echo "ok: $1"; else echo "FAIL: $1 — got '$2', want '$3'"; fail=1; fi; }

CLIPHIST_DATA_DIR="$(mktemp -d)"
export CLIPHIST_DATA_DIR
now=$(date +%s)
cat > "$CLIPHIST_DATA_DIR/history.jsonl" <<EOF
{"ts": $((now - 36000)), "app": "old.app", "text": "too old"}
{"ts": $((now - 60)), "app": "com.apple.Safari", "text": "recent one"}
not json garbage
{"ts": $((now - 5)), "app": "com.apple.Terminal", "text": "line1\nline2"}
EOF

t "json count (8h default hides 10h-old item)" "$("$CLI" list --json | grep -c ts)" "2"
t "json newest first" "$("$CLI" list --json | head -1 | grep -c line1)" "1"
t "get 0 multi-line intact" "$("$CLI" get 0)" "$(printf 'line1\nline2')"
t "get 1" "$("$CLI" get 1)" "recent one"
if "$CLI" get 99 >/dev/null 2>&1; then echo "FAIL: get out-of-range should exit 1"; fail=1; else echo "ok: get out-of-range exits 1"; fi
t "feed flattens newlines" "$("$CLI" pick-feed | head -1 | grep -c '⏎')" "1"
t "feed index prefix" "$("$CLI" pick-feed | head -1 | cut -f1)" "0"
t "-n 1 limits" "$("$CLI" list -n 1 | grep -c .)" "1"
"$CLI" retention off >/dev/null
t "retention off shows all" "$("$CLI" list --json | grep -c ts)" "3"
printf '{"app": "x", "text": "no ts field"}\n' >> "$CLIPHIST_DATA_DIR/history.jsonl"
t "missing-ts line skipped, no crash" "$("$CLI" list --json | grep -c ts)" "3"
t "feed survives missing-ts line" "$("$CLI" pick-feed | grep -c .)" "3"
printf '{"ts": null, "app": "x", "text": "null ts"}\n' >> "$CLIPHIST_DATA_DIR/history.jsonl"
t "null-ts line skipped, no crash" "$("$CLI" list --json | grep -c 'ts' )" "3"
printf '{"ts": Infinity, "app": "x", "text": "infinite ts"}\n' >> "$CLIPHIST_DATA_DIR/history.jsonl"
t "infinite-ts line skipped, no crash" "$("$CLI" list --json | grep -c 'ts')" "3"
printf '{"ts": -Infinity, "app": "x", "text": "neg-infinite ts"}\n' >> "$CLIPHIST_DATA_DIR/history.jsonl"
t "neg-infinite-ts line skipped, no crash" "$("$CLI" list --json | grep -c 'ts')" "3"
printf '{"ts": NaN, "app": "x", "text": "nan ts"}\n' >> "$CLIPHIST_DATA_DIR/history.jsonl"
t "nan-ts line skipped, no crash" "$("$CLI" list --json | grep -c 'ts')" "3"
printf '{"ts": true, "app": "x", "text": "bool ts"}\n' >> "$CLIPHIST_DATA_DIR/history.jsonl"
t "bool-ts line skipped, no crash" "$("$CLI" list --json | grep -c 'ts')" "3"
printf '{"ts": "x", "app": "x", "text": "string ts"}\n' >> "$CLIPHIST_DATA_DIR/history.jsonl"
t "string-ts line skipped, no crash" "$("$CLI" list --json | grep -c 'ts')" "3"
printf '{"ts": %s, "app": "x", "text": 123}\n' "$now" >> "$CLIPHIST_DATA_DIR/history.jsonl"
t "numeric-text line skipped, no crash" "$("$CLI" list --json | grep -c 'ts')" "3"
printf '{"ts": %s, "app": "x", "text": []}\n' "$now" >> "$CLIPHIST_DATA_DIR/history.jsonl"
t "list-text line skipped, no crash" "$("$CLI" list --json | grep -c 'ts')" "3"
printf '{"ts": %s, "app": "x", "text": ""}\n' "$now" >> "$CLIPHIST_DATA_DIR/history.jsonl"
t "empty-text line skipped, no crash" "$("$CLI" list --json | grep -c 'ts')" "3"
t "pick-feed survives all malformed rows, no traceback" "$("$CLI" pick-feed | grep -c .)" "3"
if "$CLI" list -n abc >/dev/null 2>&1; then echo "FAIL: non-numeric -n accepted"; fail=1; else echo "ok: non-numeric -n rejected"; fi
if "$CLI" list -n >/dev/null 2>&1; then echo "FAIL: missing -n value accepted"; fail=1; else echo "ok: missing -n value rejected"; fi
if "$CLI" get abc >/dev/null 2>&1; then echo "FAIL: non-numeric index accepted"; fail=1; else echo "ok: non-numeric index rejected"; fi

# Fix 1: unreadable / invalid-UTF-8 store file must not traceback
printf '\xff\xfe broken\n' > "$CLIPHIST_DATA_DIR/history.jsonl"
out=$("$CLI" list --json)
rc=$?
t "invalid-UTF-8 history: exit 0" "$rc" "0"
t "invalid-UTF-8 history: 0 rows" "$(echo "$out" | grep -c ts)" "0"
t "invalid-UTF-8 history: no traceback on stdout" "$(echo "$out" | grep -c Traceback)" "0"
exit $fail
