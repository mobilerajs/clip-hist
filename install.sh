#!/bin/bash
set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")" && pwd)"
BIN_DIR="$HOME/.local/bin"
DATA_DIR="$HOME/.local/share/clip-hist"
PLIST="$HOME/Library/LaunchAgents/com.rajsingh.clip-hist.plist"

if ! command -v swiftc >/dev/null 2>&1; then
  echo "swiftc not found. Install Command Line Tools first: xcode-select --install" >&2
  exit 1
fi

# command -v can miss a brew that was just installed in this same shell session
# (PATH hasn't been refreshed yet), so fall back to the well-known install paths.
BREW_BIN=""
if command -v brew >/dev/null 2>&1; then
  BREW_BIN="brew"
elif [[ -x /opt/homebrew/bin/brew ]]; then
  BREW_BIN="/opt/homebrew/bin/brew"
elif [[ -x /usr/local/bin/brew ]]; then
  BREW_BIN="/usr/local/bin/brew"
fi

if ! command -v fzf >/dev/null 2>&1; then
  if [[ -n "$BREW_BIN" ]]; then
    echo "Installing fzf..."
    "$BREW_BIN" install fzf || echo "warning: fzf install failed — the Ctrl+H picker won't work until you install it" >&2
  else
    echo "warning: fzf not found and Homebrew missing — the Ctrl+H picker needs fzf" >&2
  fi
fi

mkdir -p "$BIN_DIR" "$DATA_DIR" "$HOME/Library/LaunchAgents"
chmod 700 "$DATA_DIR"

echo "Compiling watcher..."
swiftc -O "$REPO_DIR/watcher/main.swift" -o "$BIN_DIR/clip-hist-watcher"

rm -f "$BIN_DIR/clip-hist"   # replace v1 symlink or old copy
install -m 755 "$REPO_DIR/bin/clip-hist" "$BIN_DIR/clip-hist"
install -m 644 "$REPO_DIR/shell/clip-hist.zsh" "$DATA_DIR/clip-hist.zsh"

# KeepAlive=true tells launchd to auto-restart the watcher if it dies, so
# `kill`/`pkill` alone will NOT stop it — use `clip-hist pause` or
# `launchctl unload "$PLIST"` instead.
cat > "$PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>com.rajsingh.clip-hist</string>
  <key>ProgramArguments</key>
  <array><string>$BIN_DIR/clip-hist-watcher</string></array>
  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key><true/>
  <key>StandardErrorPath</key><string>$DATA_DIR/watcher.log</string>
</dict>
</plist>
EOF

launchctl unload "$PLIST" 2>/dev/null || true
if ! launchctl load "$PLIST"; then
  echo "warning: watcher compiled fine, but 'launchctl load' failed — the" >&2
  echo "  background watcher isn't running. Retry with: launchctl load \"$PLIST\"" >&2
fi

ZLINE="source \"\$HOME/.local/share/clip-hist/clip-hist.zsh\""
if [[ -f "$HOME/.zshrc" ]] && grep -q 'clip-hist\.zsh' "$HOME/.zshrc"; then
  grep -Ev '^source ".*clip-hist\.zsh"$' "$HOME/.zshrc" > "$HOME/.zshrc.clip-hist.tmp" || true
  mv "$HOME/.zshrc.clip-hist.tmp" "$HOME/.zshrc"
fi
if [[ -f "$HOME/.zshrc" ]] && [[ -s "$HOME/.zshrc" ]]; then
  last_byte="$(tail -c 1 "$HOME/.zshrc")"
  if [[ -n "$last_byte" ]]; then
    printf '\n' >> "$HOME/.zshrc"
  fi
fi
printf '%s\n' "$ZLINE" >> "$HOME/.zshrc"
echo "Added source line to ~/.zshrc"

if [[ "$SHELL" != *zsh ]]; then
  echo "note: your login shell is '$SHELL', not zsh — clip-hist's Ctrl+H" >&2
  echo "  picker requires zsh. Switch with: chsh -s /bin/zsh" >&2
fi

echo
echo "clip-hist installed. Open a new terminal (or run: source ~/.zshrc), copy"
echo "something, then press Ctrl+H. Check health any time with: clip-hist status"
