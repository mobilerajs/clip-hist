#!/bin/bash
set -u
CLI="$(cd "$(dirname "$0")/.." && pwd)/bin/clip-hist"
fail=0
t() { if [[ "$2" == "$3" ]]; then echo "ok: $1"; else echo "FAIL: $1 — got '$2', want '$3'"; fail=1; fi; }

CLIPHIST_DATA_DIR="$(mktemp -d)"
export CLIPHIST_DATA_DIR
printf '{"ts": %s, "app": "com.example.seen", "text": "x"}\n' "$(date +%s)" > "$CLIPHIST_DATA_DIR/history.jsonl"

t "empty list" "$("$CLI" ignore)" "(none)"
t "toggle on" "$("$CLI" ignore com.google.Chrome)" "ignored: com.google.Chrome"
t "listed" "$("$CLI" ignore)" "com.google.Chrome"
t "retention preserved alongside" "$("$CLI" retention)" "8h"
t "toggle off" "$("$CLI" ignore com.google.Chrome)" "unignored: com.google.Chrome"
"$CLI" ignore com.example.ignored >/dev/null
inv=$("$CLI" ignore --inventory)
t "inventory checks ignored" "$(echo "$inv" | grep -c '^\[x\] com.example.ignored')" "1"
t "inventory includes seen app" "$(echo "$inv" | grep -c '^\[ \] com.example.seen')" "1"
t "inventory includes installed apps" "$([[ $(echo "$inv" | grep -c .) -gt 10 ]] && echo yes)" "yes"

# Fix 4: cmd_ignore config write is atomic + 0600 like set_config
t "config file mode 600 after toggle" "$(stat -f %Lp "$CLIPHIST_DATA_DIR/config.json")" "600"
t "no leftover tmp file after toggle" "$([[ -e "$CLIPHIST_DATA_DIR/config.json.tmp" ]] && echo leftover || echo clean)" "clean"
exit $fail
