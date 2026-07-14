#!/bin/bash
set -u
CLI="$(cd "$(dirname "$0")/.." && pwd)/bin/clip-hist"
fail=0
t() { if [[ "$2" == "$3" ]]; then echo "ok: $1"; else echo "FAIL: $1 — got '$2', want '$3'"; fail=1; fi; }

CLIPHIST_DATA_DIR="$(mktemp -d)"
export CLIPHIST_DATA_DIR

t "default retention" "$("$CLI" retention)" "8h"
"$CLI" retention 24h >/dev/null
t "set retention" "$("$CLI" retention)" "24h"
t "config file contents" "$(cat "$CLIPHIST_DATA_DIR/config.json")" '{"retention": "24h"}'
"$CLI" retention off >/dev/null
t "retention off" "$("$CLI" retention)" "off"
"$CLI" retention 30m >/dev/null
t "minutes accepted" "$("$CLI" retention)" "30m"
if "$CLI" retention 5x >/dev/null 2>&1; then echo "FAIL: invalid duration accepted"; fail=1; else echo "ok: invalid duration rejected"; fi

# Fix 2: reject all-zero durations
if "$CLI" retention 0h >/dev/null 2>&1; then echo "FAIL: zero-duration retention accepted"; fail=1; else echo "ok: zero-duration retention rejected"; fi
t "stored value unchanged after rejected zero" "$("$CLI" retention)" "30m"
if "$CLI" retention 0m >/dev/null 2>&1; then echo "FAIL: zero-minute retention accepted"; fail=1; else echo "ok: zero-minute retention rejected"; fi
if "$CLI" retention 0d >/dev/null 2>&1; then echo "FAIL: zero-day retention accepted"; fail=1; else echo "ok: zero-day retention rejected"; fi

# Fix 5a: data dir must be created 0700 by the CLI itself
NESTED_DIR="$(mktemp -d)/nested"
CLIPHIST_DATA_DIR="$NESTED_DIR" "$CLI" retention 24h >/dev/null
t "data dir created 0700" "$(stat -f %Lp "$NESTED_DIR")" "700"
exit $fail
