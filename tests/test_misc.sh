#!/bin/bash
set -u
CLI="$(cd "$(dirname "$0")/.." && pwd)/bin/clip-hist"
fail=0
t() { if [[ "$2" == "$3" ]]; then echo "ok: $1"; else echo "FAIL: $1 — got '$2', want '$3'"; fail=1; fi; }

CLIPHIST_DATA_DIR="$(mktemp -d)"
export CLIPHIST_DATA_DIR
now=$(date +%s)
printf '{"ts": %s, "app": "a", "text": "hello"}\n' "$now" > "$CLIPHIST_DATA_DIR/history.jsonl"

"$CLI" pause >/dev/null
t "pause creates sentinel" "$([[ -f "$CLIPHIST_DATA_DIR/paused" ]] && echo yes)" "yes"
t "status shows paused" "$("$CLI" status | grep -c 'recording: paused')" "1"
"$CLI" resume >/dev/null
t "resume removes sentinel" "$([[ -f "$CLIPHIST_DATA_DIR/paused" ]] || echo gone)" "gone"
t "status shows retention" "$("$CLI" status | grep -c 'retention: 8h')" "1"
t "status item count" "$("$CLI" status | grep -c 'items (within retention): 1')" "1"
"$CLI" clear --force >/dev/null
t "clear empties history" "$("$CLI" list --json | grep -c ts || true)" "0"
t "default key" "$("$CLI" key)" "^H"
"$CLI" key ctrl-k >/dev/null
t "key set via ctrl-k form" "$("$CLI" key)" "^K"
"$CLI" key '^J' >/dev/null
t "key set via caret form" "$("$CLI" key)" "^J"
"$CLI" retention 12h >/dev/null
t "retention preserves key" "$("$CLI" key)" "^J"
if "$CLI" key bogus >/dev/null 2>&1; then echo "FAIL: invalid key accepted"; fail=1; else echo "ok: invalid key rejected"; fi
saved="$(pbpaste 2>/dev/null || true)"
"$CLI" copy --quiet "agent-link-test" >/dev/null
t "copy arg (quiet)" "$(pbpaste)" "agent-link-test"
printf 'stdin-copy-test' | "$CLI" copy --quiet >/dev/null
t "copy stdin (quiet)" "$(pbpaste)" "stdin-copy-test"
t "quiet exits clean" "$("$CLI" copy --quiet ok >/dev/null 2>&1; echo $?)" "0"
printf 'trail\n\n' | "$CLI" copy --quiet >/dev/null
t "stdin trailing newlines preserved" "$(pbpaste | wc -c | tr -d ' ')" "7"
mb="$(printf 'a%.0s' 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20 21 22 23 24 25 26 27 28 29 30 31 32 33 34 35 36 37 38 39 40 41 42 43 44 45 46 47 48 49)🎉END"
t "multibyte copy exits clean" "$("$CLI" copy "$mb" 2>&1)" "copied to clipboard"
printf '%s' "$saved" | pbcopy
exit $fail
