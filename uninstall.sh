#!/bin/bash
set -euo pipefail

PLIST="$HOME/Library/LaunchAgents/com.rajsingh.clip-hist.plist"

launchctl unload "$PLIST" 2>/dev/null || true
rm -f "$PLIST" "$HOME/.local/bin/clip-hist-watcher" "$HOME/.local/bin/clip-hist"

if [[ -f "$HOME/.zshrc" ]] && grep -q 'clip-hist\.zsh' "$HOME/.zshrc"; then
  grep -Ev '^source ".*clip-hist\.zsh"$' "$HOME/.zshrc" > "$HOME/.zshrc.clip-hist.tmp" || true
  mv "$HOME/.zshrc.clip-hist.tmp" "$HOME/.zshrc"
  echo "Removed source line from ~/.zshrc"
fi

rm -f "$HOME/.local/share/clip-hist/clip-hist.zsh"

printf 'Delete clipboard history at ~/.local/share/clip-hist? [y/N] '
read -r ans
if [[ "$ans" == "y" || "$ans" == "Y" ]]; then
  rm -rf "$HOME/.local/share/clip-hist"
  echo "History deleted."
fi
echo "clip-hist uninstalled."
