#!/bin/bash
# Session-only tests for the Ctrl+S settings helpers (headless parts only —
# the fzf screens themselves are interactive and verified manually).
set -u
REPO="$(cd "$(dirname "$0")/.." && pwd)"
CLI="$REPO/bin/clip-hist"
Z="$REPO/shell/clip-hist.zsh"
export PATH="$REPO/bin:$PATH"
fail=0
t() { if [[ "$2" == "$3" ]]; then echo "ok: $1"; else echo "FAIL: $1 — got '$2', want '$3'"; fail=1; fi; }

CLIPHIST_DATA_DIR="$(mktemp -d)"
export CLIPHIST_DATA_DIR

# apply-setting retention: message + persisted value
out=$(zsh -c "source '$Z'; _clip-hist-apply-setting retention 24h; print -r -- \$_clip_hist_msg")
t "retention apply message" "$out" "retention set to 24h"
t "retention persisted" "$("$CLI" retention)" "24h"

# apply-setting key: persists, rebinds live, restores old widget on ^H
out=$(zsh -c "source '$Z'; _clip-hist-apply-setting key ctrl-k; print -r -- \$_clip_hist_msg; bindkey -- '^K'; bindkey -- '^H'")
t "key apply message" "$(echo "$out" | sed -n 1p)" "picker key set to ^K — active in this shell now"
t "new key bound live" "$(echo "$out" | sed -n 2p)" '"^K" _clip-hist-pick'
t "old key restored" "$(echo "$out" | sed -n 3p)" '"^H" backward-delete-char'
t "key persisted" "$("$CLI" key)" "^K"

# invalid key: rejected, message set, binding unchanged
out=$(zsh -c "source '$Z'; _clip-hist-apply-setting key bogus; print -r -- \$_clip_hist_msg; bindkey -- '^K'")
t "invalid key message" "$(echo "$out" | sed -n 1p)" "clip-hist: invalid key: bogus"
t "binding unchanged on invalid" "$(echo "$out" | sed -n 2p)" '"^K" _clip-hist-pick'

# source-time: widget + header wiring intact
t "widget still binds at source" "$(zsh -c "source '$Z'; bindkey | grep -c clip-hist")" "1"
t "picker advertises settings" "$(grep -c '\^S settings' "$Z")" "1"
t "picker expects ctrl-s and ctrl-p" "$(grep -c 'expect=ctrl-s,ctrl-p' "$Z")" "1"
t "ctrl-y copies in place" "$(grep -c 'ctrl-y:execute-silent(' "$Z")" "1"
t "picker sets a session pause sentinel (stale-index fix)" "$([[ $(grep -c 'pre_paused' "$Z") -ge 1 ]] && echo yes)" "yes"
t "ctrl-y no longer runs its own pause dance" "$(grep -c 'sleep 0.7' "$Z")" "0"
t "ctrl-y confirms via header" "$(grep -c 'change-header(copied to clipboard' "$Z")" "1"
t "picker has preview" "$(grep -c -- '--preview "command clip-hist get {1}' "$Z")" "1"
t "preview sanitizes escape bytes" "$(grep -c 's/\\\\x1b/\^\[/g' "$Z")" "1"
t "preview toggle bound" "$(grep -c 'ctrl-/:toggle-preview' "$Z")" "1"
t "header advertises pin" "$(grep -c '\^P pin' "$Z")" "1"
t "header restores after copy" "$(grep -c 'change:change-header' "$Z")" "1"
t "settings offers wipe" "$([[ $(grep -c 'Wipe history' "$Z") -ge 1 ]] && echo yes)" "yes"
t "secrets label says what it does" "$(grep -c 'Secrets: not recorded' "$Z")" "1"
t "esc clears query before closing" "$(grep -c 'esc:transform' "$Z")" "1"
t "esc rule on every screen" "$(grep -c -- '--bind "\$_clip_hist_esc"' "$Z")" "6"

exit $fail
