# clip-hist — clipboard history picker for zsh.
# Sourced from .zshrc by install.sh. Keybinding resolution (first wins):
# CLIPHIST_KEY env var > `clip-hist key` config value > ^H.
# Change persistently with: clip-hist key ctrl-k, or Ctrl+S inside the picker.

[[ ":$PATH:" == *":$HOME/.local/bin:"* ]] || export PATH="$PATH:$HOME/.local/bin"

# Esc clears a non-empty search query; on an empty query it aborts (backs out).
typeset -g _clip_hist_esc='esc:transform:[ -n "$FZF_QUERY" ] && echo clear-query || echo abort'

# Bind $1 to the picker; restore the previous widget on the old key so a
# rebind never leaves e.g. backspace (^H) dead in terminals that send it.
_clip-hist-bind() {
  emulate -L zsh
  local new="$1" prev
  if [[ -n "${_clip_hist_bound_key:-}" && "$_clip_hist_bound_key" != "$new" ]]; then
    if [[ -n "${_clip_hist_prev_widget:-}" && "$_clip_hist_prev_widget" != "undefined-key" ]]; then
      bindkey -- "$_clip_hist_bound_key" "$_clip_hist_prev_widget"
    else
      bindkey -r -- "$_clip_hist_bound_key" 2>/dev/null
    fi
  fi
  prev="${$(bindkey -- "$new")##* }"
  [[ "$prev" == "_clip-hist-pick" ]] || typeset -g _clip_hist_prev_widget="$prev"
  typeset -g _clip_hist_bound_key="$new"
  bindkey -- "$new" _clip-hist-pick
}

# Apply one setting ($1 = retention|key, $2 = value). Runs in the CURRENT
# shell (never a subshell) so a key change can rebind live; the outcome
# message is left in $_clip_hist_msg for the widget to flash via zle -M.
_clip-hist-apply-setting() {
  emulate -L zsh
  typeset -g _clip_hist_msg=""
  case "$1" in
    retention)
      _clip_hist_msg=$(command clip-hist retention "$2" 2>&1)
      ;;
    key)
      if ! command clip-hist key "$2" >/dev/null 2>&1; then
        _clip_hist_msg="clip-hist: invalid key: $2"
        return 1
      fi
      local newkey
      newkey=$(command clip-hist key 2>/dev/null || echo '^H')
      _clip-hist-bind "$newkey"
      _clip_hist_msg="picker key set to $newkey — active in this shell now"
      ;;
  esac
}

# Settings screens (Ctrl+S from the picker). Never mixed into the history
# rows — the picker swaps to a separate two-item list. Esc here returns to
# the clipboard picker; Esc in a value list returns to this settings list.
# Returning (after Esc or an applied change) always lands back in the picker.
_clip-hist-settings() {
  emulate -L zsh
  typeset -g _clip_hist_msg=""
  local cur_ret cur_key cur_sec sec_label choice value
  while true; do
    cur_ret=$(command clip-hist retention 2>/dev/null || echo '8h')
    cur_key=$(command clip-hist key 2>/dev/null || echo '^H')
    cur_sec=$(command clip-hist secrets 2>/dev/null || echo on)
    if [[ $cur_sec == on ]]; then
      sec_label='Secrets: not recorded (detection on)'
    else
      sec_label='Secrets: recorded (detection off)'
    fi
    choice=$(printf 'Retention: %s\nPicker key: %s\nIgnored apps\n%s\nWipe history...\n' "$cur_ret" "$cur_key" "$sec_label" | \
      fzf --height=40% --reverse --no-multi --bind "$_clip_hist_esc" \
          --prompt='settings> ' \
          --header='enter: change · esc: back to clipboard') || return 0
    case "$choice" in
      'Retention:'*)
        value=$(printf '%s\n' 30m 1h 4h 8h 24h 2d 7d off | \
          fzf --height=40% --reverse --no-multi --bind "$_clip_hist_esc" \
          --prompt='retention> ' \
              --header="current: $cur_ret · esc: back to settings") || continue
        _clip-hist-apply-setting retention "$value"
        return 0
        ;;
      'Picker key:'*)
        value=$(printf 'ctrl-%s\n' h g k o b v n t | \
          fzf --height=40% --reverse --no-multi --bind "$_clip_hist_esc" \
          --prompt='picker key> ' \
              --header="current: $cur_key · esc: back to settings") || continue
        _clip-hist-apply-setting key "$value"
        return 0
        ;;
      'Ignored apps'*)
        local inv sel row
        local -a ids
        inv=$(command clip-hist ignore --inventory)
        sel=$(print -r -- "$inv" | fzf --multi --height=60% --reverse \
              --bind "$_clip_hist_esc" \
          --prompt='ignored apps> ' \
              --header='tab: select · enter: toggle selected · esc: back to settings') || continue
        [[ -n "$sel" ]] || continue
        ids=()
        while IFS= read -r row; do ids+=("${row#\[?\] }"); done <<< "$sel"
        if (( ${#ids} )); then
          command clip-hist ignore "${ids[@]}" >/dev/null 2>&1
          typeset -g _clip_hist_msg="ignored-apps list updated"
        fi
        return 0
        ;;
      'Secrets:'*)
        if [[ $cur_sec == on ]]; then
          command clip-hist secrets off >/dev/null 2>&1
        else
          command clip-hist secrets on >/dev/null 2>&1
        fi
        continue
        ;;
      'Wipe history...'*)
        value=$(printf 'Wipe history (keep pins)\nWipe everything (history + pins)\n' | \
          fzf --height=40% --reverse --no-multi --bind "$_clip_hist_esc" \
          --prompt='wipe> ' \
              --header='this cannot be undone · esc: back to settings') || continue
        case "$value" in
          'Wipe history (keep pins)')
            command clip-hist clear --force >/dev/null 2>&1
            typeset -g _clip_hist_msg="history wiped (pins kept)"
            ;;
          'Wipe everything'*)
            command clip-hist clear --all --force >/dev/null 2>&1
            typeset -g _clip_hist_msg="history and pins wiped"
            ;;
        esac
        return 0
        ;;
    esac
  done
}

_clip-hist-pick() {
  emulate -L zsh
  setopt local_options pipefail
  if ! command -v clip-hist >/dev/null 2>&1; then
    zle -M "clip-hist: CLI not found in PATH"
    return 1
  fi
  if ! command -v fzf >/dev/null 2>&1; then
    zle -M "clip-hist: fzf not installed — brew install fzf"
    return 1
  fi
  local out key line idx text
  # hdr is interpolated raw into fzf's change-header(...) action below — it
  # must stay free of ',' and '(' ')' or the bind string breaks.
  local hdr='enter insert · ^Y copy · ^P pin · ^S settings · ^D/^U scroll'
  typeset -g _clip_hist_msg=""

  # Pause recording for the whole picker session, not just around a single
  # copy: while the picker is open the watcher can still append/reorder/
  # prune history, which would shift the row indexes captured from
  # pick-feed out from under the user (get/pin/ctrl-y would silently act on
  # the wrong item). Pausing here — and resuming in the always-block below,
  # which runs on every exit path including esc/abort and early returns —
  # freezes the list for the session's lifetime instead. Tradeoff: copies
  # made in other apps while the picker is open are not recorded; acceptable
  # since the picker is typically open only briefly. If a pause was already
  # active before this widget ran, leave it active on exit (don't resume
  # someone else's pause). If the whole shell is killed while the picker
  # holds the sentinel it can orphan — `clip-hist resume` clears a stuck pause.
  local P="${CLIPHIST_DATA_DIR:-$HOME/.local/share/clip-hist}"
  local S="$P/paused"
  local pre_paused=0
  [[ -e "$S" ]] && pre_paused=1
  {
    [[ $pre_paused == 0 ]] && { mkdir -p "$P"; touch "$S"; }
    while true; do
      out=$(clip-hist pick-feed | fzf --delimiter=$'\t' --with-nth=2 \
            --height=60% --reverse --no-multi --expect=ctrl-s,ctrl-p \
            --header="$hdr" \
            --preview "command clip-hist get {1} | LC_ALL=C sed 's/\\x1b/^[/g'" \
            --preview-window='down,30%,wrap' \
            --bind 'ctrl-/:toggle-preview,ctrl-u:preview-page-up,ctrl-d:preview-page-down,shift-up:preview-up,shift-down:preview-down' \
            --bind 'ctrl-y:execute-silent(command clip-hist get {1} | pbcopy)+change-header(copied to clipboard · esc close · enter insert)' \
            --bind "up:up+change-header($hdr),down:down+change-header($hdr),change:change-header($hdr)" \
            --bind "$_clip_hist_esc" \
            --prompt='clipboard> ') || {
        zle reset-prompt
        [[ -n "${_clip_hist_msg:-}" ]] && zle -M "clip-hist: $_clip_hist_msg" && typeset -g _clip_hist_msg=""
        return 0
      }
      key=${out%%$'\n'*}
      if [[ $key == ctrl-s ]]; then
        _clip-hist-settings   # returns to the clipboard picker (loop)
        continue
      fi
      if [[ $key == ctrl-p ]]; then
        line=${out#*$'\n'}
        idx=${line%%$'\t'*}
        [[ "$idx" == <-> ]] && command clip-hist pin "$idx" >/dev/null 2>&1
        continue
      fi
      break
    done
    line=${out#*$'\n'}
    idx=${line%%$'\t'*}
    text=$(clip-hist get "$idx") || { zle reset-prompt; return 1 }
    LBUFFER+="$text"
    zle reset-prompt
  } always {
    [[ $pre_paused == 0 ]] && rm -f "$S"
  }
}
zle -N _clip-hist-pick
_clip-hist-bind "${CLIPHIST_KEY:-$(command clip-hist key 2>/dev/null || echo '^H')}"
