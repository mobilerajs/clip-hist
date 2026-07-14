# clip-hist — macOS clipboard history with a terminal picker

**Date:** 2026-07-14
**Status:** Approved (design), pending spec review

## Purpose

macOS keeps only the current clipboard item. clip-hist records every copy made
anywhere on the system (Cmd+C, right-click Copy, menu bar, Universal Clipboard
from iPhone) and makes the history selectable from the terminal: a keyboard
shortcut opens a picker, arrow keys / typing filter the list, Enter inserts the
chosen item at the cursor on the command line.

Primary user: Raj (personal productivity + agent workflows). Secondary goal:
open-source the tool, so the approach must be sound — privacy-respecting,
dependency-light, easy to install and uninstall.

## Architecture

Three parts: **watcher** (captures), **store** (persists), **picker/CLI**
(consumes).

```
NSPasteboard ──poll 0.3s──> clip-hist-watcher (Swift, launchd agent)
                                   │ append (dedupe, cap, filter)
                                   v
                    ~/.local/share/clip-hist/history.jsonl  (chmod 600)
                                   │
                 ┌─────────────────┴──────────────────┐
                 v                                    v
        zsh widget (Ctrl+H) → fzf picker      clip-hist CLI (list/clear/
        Enter = insert at cursor              pause/resume/status) —
        Ctrl+Y = re-copy to clipboard         also the agent interface
```

### 1. Watcher — `clip-hist-watcher`

- ~60-line Swift program, compiled at install time with `swiftc` (no Xcode
  project). Runs as a launchd user agent (`com.rajsingh.clip-hist.plist` in
  `~/Library/LaunchAgents`): starts at login, `KeepAlive` restarts it if it
  dies.
- Polls `NSPasteboard.general.changeCount` every 0.3s — effectively zero CPU;
  the same technique Maccy uses. Reading the pasteboard requires no macOS
  privacy permissions.
- On change, reads the plain-text representation and appends a JSONL record.
- **Skips**:
  - items marked `org.nspasteboard.ConcealedType` or
    `org.nspasteboard.TransientType` (password managers set these — 1Password,
    Bitwarden, etc.)
  - empty / whitespace-only text
  - non-text-only items (images, files) — text-only for v1
  - duplicates: history is unique by text content — re-copying text that is
    already stored removes the older entry and appends fresh (move-to-top;
    changed from consecutive-only dedupe post-v1.1). Picker Ctrl+Y copies
    are excluded: the widget wraps its pbcopy in the pause sentinel
    (~0.7s) so the watcher never records them and list order is stable.
  - anything while paused (presence of a `pause` sentinel file)
- **Universal Clipboard:** copying on a nearby iPhone (same Apple ID, Handoff
  on) bumps the Mac pasteboard; the watcher's read forces the transfer, so
  iPhone copies are captured automatically. Limits (documented in README):
  iPhone must be in Bluetooth range of the awake Mac, and iOS offers the item
  for only ~2 minutes after copying.

### 2. Store — `~/.local/share/clip-hist/history.jsonl`

- One JSON object per line: `{"ts": <unix seconds>, "app": "<source bundle id
  or app name>", "text": "<clipboard text>"}`. Newest appended last.
- File mode `600`; directory created by the installer.
- **Retention (primary limit): items older than 8 hours are pruned.** Default
  `8h`, user-configurable via the CLI (`clip-hist retention 24h`); accepts
  `Nm`/`Nh`/`Nd`, or `off` to keep forever. Stored in
  `~/.local/share/clip-hist/config.json`; the watcher re-reads it on each
  append, so changes take effect without a restart.
- Backstop caps enforced by the watcher on append: max **500 items** (oldest
  lines trimmed), max **100 KB per item** (larger items skipped).
- Trimming strategy: on each append, drop lines older than the retention
  window and beyond the item cap by rewriting the file. Single-writer (the
  watcher), so no locking needed; readers tolerate a torn last line by
  skipping unparseable lines. Readers also filter expired lines at display
  time so a lowered retention applies immediately.
- Known accepted race (no file lock, by design): `clip-hist clear`
  truncates the same file the watcher rewrites. A clear that lands while
  the watcher is mid-append can be overwritten by the watcher's buffered
  copy. Worst case: re-run clear. Cross-language locking (Swift + bash +
  python) isn't worth this failure mode.
- Agents consume it via `clip-hist list --json` (or `jq` directly on the file).
  Agent access is **read-only** by convention — nothing in v1 writes to the
  store except the watcher.

### 3. Picker + CLI — `clip-hist` (shell script) + zsh widget

- `clip-hist.zsh` (sourced from `.zshrc`) defines a ZLE widget bound to
  **Ctrl+H** by default. Overridable two ways: persistently via
  `clip-hist key ctrl-k` (stored in config.json, read at source time) or
  per-shell via `CLIPHIST_KEY` exported before sourcing (env var wins).
  Ctrl+H is the backspace control code in some terminal setups; default macOS
  Terminal/iTerm send DEL for backspace, so it's normally free:
  - Runs fzf over the history, newest first.
  - Each row: single line with newlines shown as `⏎`, prefixed with relative
    time and source app (e.g. `2m Safari  https://…`).
  - **Enter** inserts the original (multi-line-intact) text at the cursor via
    `LBUFFER+=`.
  - **Ctrl+Y** inside the picker copies the item back to the system clipboard
    (`pbcopy`) instead of inserting.
  - **Ctrl+S** inside the picker opens a settings menu (added post-v1):
    settings never appear as rows in the history list — the picker swaps to
    a two-item screen showing current values (`Retention: 8h`,
    `Picker key: ^H`); Enter opens a value list (retention:
    30m/1h/4h/8h/24h/2d/7d/off; key: free ctrl-<letter> choices); a pick is
    applied via the existing `clip-hist retention`/`key` commands, and a key
    change also rebinds live in the current shell (restoring the previous
    widget on the old key). Navigation is a loop: Esc in a value list
    returns to the settings list; Esc in settings (or applying a change)
    returns to the clipboard picker; Esc in the picker closes. A one-line
    fzf header on each screen states where Esc goes.
  - Typing filters (fzf fuzzy search); Up/Down navigate.
- `clip-hist` CLI subcommands:
  - `list [--json] [-n N]` — newest first; human table or raw JSONL
  - `clear` — truncate history (with confirmation unless `--force`)
  - `copy [TEXT]` — copy TEXT (or stdin) to the system clipboard via
    `pbcopy`. The sanctioned **agent write path** ("here's your link, it's
    on your clipboard"); the watcher records it like any other copy.
    Write-vs-read asymmetry is enforced at the agent-harness level
    (allowlist `clip-hist copy`; keep `list`/`get`/`pbpaste` behind
    permission prompts), not the OS — same-user processes can always read
    the pasteboard. README documents this honestly.
  - `pause` / `resume` — create/remove the sentinel file the watcher checks
  - `retention [DURATION]` — show or set the retention window (e.g. `8h`,
    `2d`, `off`); default 8h
  - `key [BINDING]` — show or set the picker keybinding (accepts `^K` or
    `ctrl-k`); stored in `config.json`, applied when a new shell sources
    `clip-hist.zsh`. Resolution order: `CLIPHIST_KEY` env var >
    `config.json` > `^H` default
  - `status` — watcher running? paused? retention setting, item count, file
    size
- Dependency: **fzf** (brew). The widget degrades with a clear error message
  if fzf is missing.

## Repo layout

```
clip-hist/
├── README.md            # install, usage, Universal Clipboard notes, privacy
├── LICENSE              # MIT
├── install.sh           # compile watcher, install plist, add zshrc line,
│                        # brew install fzf if missing
├── uninstall.sh         # unload plist, remove binary/plist/zshrc line;
│                        # prompts before deleting history file
├── watcher/
│   └── main.swift
├── bin/
│   └── clip-hist         # CLI (bash/zsh script)
└── shell/
    └── clip-hist.zsh     # ZLE widget + bindkey
```

Repo lives at `the repo root`, standalone, MIT-licensed, no
co-author attribution in commits.

## Error handling

- Watcher crash → launchd restarts it; `clip-hist status` reports if it's down.
- Store missing/corrupt line → readers skip unparseable lines; watcher
  recreates the file if deleted.
- fzf missing → widget prints one-line install hint instead of failing
  silently.
- `swiftc` missing at install (no Command Line Tools) → install.sh detects and
  instructs `xcode-select --install`.

## Testing

Per global rules, tests are session-only verification (not committed):

- **Unit:** feed the store-trim and dedupe logic synthetic JSONL; verify caps,
  dedupe, torn-line tolerance. Verify CLI subcommands against a fixture file.
- **E2E:** with the watcher running: `pbcopy` several items (incl. multi-line
  and a >100 KB item), assert history contents; test pause/resume; simulate a
  concealed-type copy via a small Swift snippet and assert it is NOT recorded;
  invoke the widget's underlying function and assert insertion text.

## v1.1 additions (approved 2026-07-14)

1. **Pins.** Separate store `~/.local/share/clip-hist/pins.jsonl` (same record
   shape, mode 600, max 100 pins — adding beyond that is refused with a
   message). Pins are exempt from retention and from `clear`; `clear --all`
   wipes both stores. The picker shows pins at the top of the list, marked
   with a `*` in the row; **Ctrl+P** toggles pin/unpin on the highlighted
   item (by text identity) and loops back into the picker. `list --json`
   includes `"pinned": true` on pin rows; `clip-hist pin INDEX` is the CLI
   equivalent (combined newest-first index shared with `list`/`get`).
   `status` reports the pin count.
2. **Preview pane.** fzf `--preview 'clip-hist get {1}'` shows the full
   multi-line text inline beside the list, updating as you move; `ctrl-/`
   toggles the pane. No extra keystroke to see content.
3. **Ignored apps.** `config.json` gains `"ignored_apps": [bundle ids]`; the
   watcher skips copies whose frontmost app is in the list. CLI:
   `clip-hist ignore` (show), `clip-hist ignore ID…` (toggle each),
   `clip-hist ignore --inventory` (checklist lines `[x]/[ ] bundle-id` from
   the union of apps seen in history/pins, an `mdls` scan of /Applications,
   /System/Applications, ~/Applications, and currently ignored ids).
   Settings menu gains an `Ignored apps` screen: fzf multi-select, Tab
   toggles, Enter applies (each selected row flips), Esc backs out.
4. **Secret detection** (default ON). `config.json` `"skip_secrets": "on"`.
   The watcher refuses to record clipboard text that looks like a
   credential: known prefixes (`ghp_`, `github_pat_`, `gho_`, `sk-`,
   `AKIA`, `xoxb-`/`xoxp-`, `AIza`), JWTs (`eyJ…`), PEM private-key blocks,
   and single high-entropy tokens (length 32–256, ≥3 character classes,
   Shannon entropy ≥ 4.0 bits/char, not a URL or path). False positives
   fail safe (item just isn't recorded). CLI `clip-hist secrets [on|off]`;
   settings menu row `Secret detection: on` toggles in place.
5. **Copy notification.** `clip-hist copy` posts a macOS notification via
   `osascript` (title clip-hist, body = first ~50 chars, quotes/backslashes
   stripped) so an agent-initiated copy is visible outside the terminal.
   Default on; `--quiet` suppresses. Notification failure never fails the
   copy.
6. **Open-source hygiene.** install.sh copies `bin/clip-hist` and
   `shell/clip-hist.zsh` to fixed locations (`~/.local/bin`,
   `~/.local/share/clip-hist/clip-hist.zsh`) instead of symlinking/sourcing
   into the repo — the repo can be moved or deleted after install; updates
   require re-running install.sh. The zshrc hook sources the fixed path;
   the installer removes any stale `clip-hist.zsh` source lines before
   appending. **Tests are committed in this repo from v1.1 on** (explicit
   exception to the session-only rule, approved by Raj) and run in GitHub
   Actions CI on macOS (shellcheck + zsh -n + swiftc build + the
   non-clipboard test suites). Homebrew tap: after the repo is published.

## Out of scope (v1)

- Images, files, rich text (RTF/HTML) — plain text only
- Search across history beyond fzf filtering
- Sync across machines
- Agent write access to the store
- Linux/Wayland support (naming note: named `clip-hist` — hyphenated — to
  avoid clashing with the unrelated Wayland tool `cliphist`)
