#!/bin/bash
set -u
CLI="$(cd "$(dirname "$0")/.." && pwd)/bin/clip-hist"
fail=0
t() { if [[ "$2" == "$3" ]]; then echo "ok: $1"; else echo "FAIL: $1 — got '$2', want '$3'"; fail=1; fi; }
CLIPHIST_DATA_DIR="$(mktemp -d)"
export CLIPHIST_DATA_DIR
t "default on" "$("$CLI" secrets)" "on"
t "set off" "$("$CLI" secrets off)" "secret detection off"
t "reads off" "$("$CLI" secrets)" "off"
t "set on" "$("$CLI" secrets on)" "secret detection on"
t "retention preserved" "$("$CLI" retention)" "8h"
if "$CLI" secrets bogus >/dev/null 2>&1; then echo "FAIL: bogus accepted"; fail=1; else echo "ok: bogus rejected"; fi
exit $fail
