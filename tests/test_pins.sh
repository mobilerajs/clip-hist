#!/bin/bash
set -u
CLI="$(cd "$(dirname "$0")/.." && pwd)/bin/clip-hist"
fail=0
t() { if [[ "$2" == "$3" ]]; then echo "ok: $1"; else echo "FAIL: $1 — got '$2', want '$3'"; fail=1; fi; }

CLIPHIST_DATA_DIR="$(mktemp -d)"
export CLIPHIST_DATA_DIR
now=$(date +%s)
cat > "$CLIPHIST_DATA_DIR/history.jsonl" <<EOF
{"ts": $((now - 120)), "app": "com.apple.Safari", "text": "older item"}
{"ts": $((now - 5)), "app": "com.apple.Terminal", "text": "newest item"}
EOF

t "pin history item" "$("$CLI" pin 1)" "pinned"
t "pinned appears first" "$("$CLI" get 0)" "older item"
t "history slot follows pins" "$("$CLI" get 1)" "newest item"
t "pinned item shown once, not duplicated in list --json" "$("$CLI" list --json | grep -c '"text": "older item"')" "1"
t "pinned item shown once, not duplicated in pick-feed" "$("$CLI" pick-feed | grep -c 'older item')" "1"
t "list --json has exactly 2 rows (no cross-store dup)" "$("$CLI" list --json | grep -c ts)" "2"
t "feed marks pin" "$("$CLI" pick-feed | head -1 | grep -c '\*')" "1"
t "json pinned flag" "$("$CLI" list --json | head -1 | grep -c '"pinned": true')" "1"
t "status shows pins" "$("$CLI" status | grep -c 'pins: 1')" "1"
t "unpin by toggle" "$("$CLI" pin 0)" "unpinned"
t "pins file empty after unpin" "$("$CLI" status | grep -c 'pins: 0')" "1"
"$CLI" pin 1 >/dev/null   # re-pin "older item"
"$CLI" clear --force >/dev/null
t "clear keeps pins" "$("$CLI" status | grep -c 'pins: 1')" "1"
"$CLI" clear --all --force >/dev/null
t "clear --all wipes pins" "$("$CLI" status | grep -c 'pins: 0')" "1"
# pins survive retention: seed an ancient pin directly
printf '{"ts": 1000, "app": "x", "text": "ancient pin"}\n' > "$CLIPHIST_DATA_DIR/pins.jsonl"
t "pins exempt from retention" "$("$CLI" get 0)" "ancient pin"
t "pins file mode 600" "$(stat -f %Lp "$CLIPHIST_DATA_DIR/pins.jsonl")" "600"
# history is empty, pins has 1 item; the fix makes items count exclude pins
t "status items excludes pins" "$("$CLI" status | grep -c 'items (within retention): 0')" "1"
t "tmp file perms mode" "$([[ -e "$CLIPHIST_DATA_DIR/pins.jsonl.tmp" ]] && echo leftover || echo clean)" "clean"
exit $fail
