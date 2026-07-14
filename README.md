# clip-hist

**macOS only.** clip-hist relies on NSPasteboard, launchd, and
`pbcopy`/`pbpaste` — it does not work on Windows or Linux. It runs on both
Apple Silicon and Intel Macs.

A lightweight clipboard history for macOS. A background watcher records
every text copy you make, and a Ctrl+H picker (via `fzf`) lets you search
and re-insert anything you've copied recently — right from your terminal.

Not related to [`cliphist`](https://github.com/sentriz/cliphist), the
Wayland/Linux clipboard manager — same idea, different platform, no shared
code.

## Quickstart

```sh
git clone https://github.com/mobilerajs/clip-hist && cd clip-hist && ./install.sh
```

Then open a new terminal, copy a few things, and press **Ctrl+H**.

## Requirements

- **macOS** — Apple Silicon or Intel.
- A **zsh** login shell — the Ctrl+H picker is a zsh widget; if your login
  shell is bash you won't get it. Check with `echo $SHELL`; switch with
  `chsh -s /bin/zsh`.
- **Xcode Command Line Tools** (`xcode-select --install`) — needed to
  compile the watcher (`swiftc`).
- **Homebrew** — used by `install.sh` to install `fzf` if it isn't already
  on your machine.
- **fzf** — a hard requirement for the Ctrl+H picker; `install.sh` installs
  it via Homebrew if missing.

The background watcher (the part that records your clipboard) is a
compiled binary run by launchd — it works without fzf or zsh. The Ctrl+H
picker needs both: zsh to bind the key, fzf to render the list.

## Install

```sh
git clone https://github.com/mobilerajs/clip-hist
cd clip-hist
./install.sh
```

`install.sh` compiles the watcher, installs it as a launchd agent
(`com.rajsingh.clip-hist`) so it starts on login and stays running, copies
the `clip-hist` CLI to `~/.local/bin`, and copies the picker script into
`~/.local/share/clip-hist/` — then appends one `source` line to your
`~/.zshrc` (pointing at that fixed path) to wire up the Ctrl+H picker. That
source line also adds `~/.local/bin` to your `PATH`, but only for
interactive zsh sessions. Open a new terminal tab (or run `source
~/.zshrc`) afterward — after that, the `clip-hist` command and the Ctrl+H
picker both work in your zsh sessions. If you want `clip-hist` on `PATH`
in other shells too, add `~/.local/bin` to your `PATH` there yourself.

Everything installed lives at fixed paths outside the repo, so you're free
to move or delete the cloned repo afterward. To pick up changes (including
`git pull`s), re-run `./install.sh` — edits inside the repo aren't live
until you do, since install copies files rather than linking to them:

```sh
git pull && ./install.sh
```

## Troubleshooting

- **Ctrl+H does nothing.** Confirm your login shell is zsh (`echo
  $SHELL`) — bash doesn't get the picker. Make sure you opened a new
  terminal (or ran `source ~/.zshrc`) after installing. If your terminal
  sends Ctrl+H for backspace instead of DEL, rebind: `clip-hist key
  ctrl-k`.
- **Watcher not running.** Run `clip-hist status` to check. If it says
  "NOT running," re-run `./install.sh`.
- **`fzf: command not found`.** Run `brew install fzf`, then open a new
  terminal.

Uninstall anytime with `./uninstall.sh` — see [Uninstall](#uninstall)
below for what it does and doesn't remove.

## Usage

Copy things normally. Press **Ctrl+H** in any terminal to open the picker:

- Type to fuzzy-filter your clipboard history
- **Enter** inserts the selected text at your cursor
- **Ctrl+Y** re-copies the selected text to the clipboard; the picker stays
  open (the header confirms the copy) so you can copy more or Esc out and
  paste elsewhere with Cmd+V
- **Ctrl+P** pins (or unpins) the selected item — see Pins below
- **Ctrl+S** opens the settings menu — change retention, the picker key,
  ignored apps, or secret detection, or wipe history without leaving the
  picker (a key change takes effect in the current shell immediately)
- **Esc**: if you've typed a search query, the first Esc just clears it,
  so you can start a new search without leaving the picker. Only once the
  query is already empty does Esc back out — closing the picker from the
  clipboard list, or stepping back one screen from a settings screen
  (settings → clipboard list; a value list inside settings → settings)
- A full-width preview pane along the bottom shows the text of the selected
  item; scroll it with **ctrl-d/ctrl-u**, toggle it with **ctrl-/**

CLI:

| Command | What it does |
|---|---|
| `clip-hist list [-n N] [--json]` | Show history, newest first |
| `clip-hist get INDEX` | Print the raw text of item `INDEX` (from `list`) |
| `clip-hist pin INDEX` | Pin or unpin item `INDEX` (from `list`) |
| `clip-hist retention [DURATION]` | Show or set retention (`30m`, `8h`, `2d`, `off`) |
| `clip-hist key [BINDING]` | Show or persistently rebind the picker key |
| `clip-hist ignore [--inventory\|ID…]` | Show ignored apps, list all seen/installed apps with checkmarks (`--inventory`), or toggle app IDs |
| `clip-hist secrets [on\|off]` | Show or set credential-shaped-copy skipping (default `on`) |
| `clip-hist copy [--quiet] [TEXT]` | Copy `TEXT` (or stdin) to the clipboard, with a notification unless `--quiet` — the sanctioned write path for agents |
| `clip-hist clear [--all] [--force]` | Delete history (`--all` also wipes pins; prompts unless `--force`) |
| `clip-hist pause` / `clip-hist resume` | Stop/resume recording new copies |
| `clip-hist status` | Watcher state, recording state, retention, item and pin counts |

## Pins

Pin an item to keep it around no matter what: press **Ctrl+P** on the
selected item in the picker, or run `clip-hist pin INDEX` (the index comes
from `clip-hist list`). Pins survive both retention aging and a plain
`clip-hist clear`; only `clip-hist clear --all` wipes pins along with
history.

A few things worth knowing:

- Up to **100** pins are kept; pinning beyond that is rejected until you
  unpin something.
- Toggling is by text identity, not list position: pinning a copy of text
  that's already pinned unpins the original instead of creating a second
  pin. This is intentional — a given piece of text is either pinned or
  it isn't.
- Pinned items always sort above unpinned history in `list` and the
  picker, most-recently-pinned first.

## Preview pane

The picker shows an inline preview of the full text of the highlighted
item in a full-width pane along the bottom. Scroll it with **ctrl-d**
(page down) / **ctrl-u** (page up), and toggle it on or off with
**ctrl-/**.

## Retention

Default retention is **8 hours** — items older than that age out on the
next copy event. Change it with:

```sh
clip-hist retention 24h
clip-hist retention off   # keep everything
```

Independent of retention, there's a backstop: the history never grows past
**500 items**, and any single copy larger than **100 KB** is never
recorded in the first place (it's silently skipped, not truncated). Pins
are exempt from both the retention window and the 500-item cap.

## Privacy

- History lives in a single local file, `~/.local/share/clip-hist/history.jsonl`,
  created with mode `600` (readable only by you). Nothing leaves your machine.
- The watcher skips copies flagged by the source app as sensitive —
  password managers and similar tools mark clipboard writes with
  `org.nspasteboard.ConcealedType` or `org.nspasteboard.TransientType`,
  and those are never written to history.
- Whitespace-only and non-text copies are ignored; history is deduped by
  content — copying text that's already in history moves it to the top
  instead of duplicating. Picker re-copies (Ctrl+Y) are the exception:
  they're not re-recorded at all, so the list order doesn't shift under you.
- Run `clip-hist pause` before anything sensitive you don't want recorded
  (secrets, one-off tokens, etc.), and `clip-hist resume` when you're done.
- `clip-hist clear` wipes history but leaves pins alone; `clip-hist clear
  --all` wipes both.

Note: this is app-level hygiene, not a security boundary. See Agents below
for why the OS itself can't enforce read restrictions on the pasteboard.

## Ignored apps

Stop specific apps from ever having their copies recorded. From the picker,
press **Ctrl+S** then choose "Ignored apps" for a checklist (tab to toggle,
enter to apply) covering every app clip-hist has seen a copy from plus
everything installed on your Mac. From the CLI:

```sh
clip-hist ignore                # list currently-ignored app IDs
clip-hist ignore --inventory    # full checklist: [x] ignored, [ ] not
clip-hist ignore com.google.Chrome   # toggle one (or more) app IDs
```

App IDs are bundle identifiers (e.g. `com.google.Chrome`); the watcher
compares the frontmost app at copy time against this list and silently
skips recording if it matches.

## Secret detection

clip-hist skips copies that look like credentials by default, so tokens
and keys don't end up sitting in plaintext history. It catches:

- PEM-style private key blocks
- Common token prefixes: GitHub (`ghp_`, `github_pat_`, `gho_`), OpenAI
  (`sk-`), AWS (`AKIA`), Slack (`xoxb-`, `xoxp-`), Google (`AIza`)
- JWTs (`eyJ…` with dots and sufficient length)
- Generic high-entropy strings: 32-256 chars, no whitespace, mixing at
  least 3 character classes, above a Shannon entropy threshold

Turn it off (or back on) with:

```sh
clip-hist secrets off
clip-hist secrets on
```

or via Ctrl+S → "Secret detection" in the picker. Be aware this is a
heuristic, not a guarantee — it will miss some secrets (short tokens,
low-entropy passwords) and can occasionally flag ordinary copies (random
IDs, hashes). Don't treat it as a substitute for `clip-hist pause` when
you know you're about to copy something sensitive.

## Copy notifications

`clip-hist copy` shows a macOS notification with a snippet of what was
copied by default, so you (or whoever's watching the screen) can see an
agent's write land. Suppress it with `--quiet`:

```sh
clip-hist copy --quiet "no notification for this one"
```

## Agents

`clip-hist copy [TEXT]` (or piping text into `clip-hist copy` via stdin) is
the sanctioned way for an agent to hand you something on your clipboard —
a link, a generated snippet, whatever. `clip-hist list --json` and
`clip-hist get INDEX` are the read paths, for an agent that needs to look
back at what's been copied.

If you're wiring clip-hist into an agent harness, it's worth enforcing a
write-vs-read asymmetry at the harness level: let the agent freely run
`clip-hist copy`, but keep `clip-hist list`, `clip-hist get`, and `pbpaste`
behind a permission prompt. In Claude Code, for example, that means
allowlisting `clip-hist copy` while leaving the read commands out of the
allowlist.

Be clear-eyed about the limits of this: it's a harness-level convention,
not an OS-enforced boundary. Any process running as your user can read the
system pasteboard directly with `pbpaste` or the Pasteboard APIs — nothing
in macOS scopes clipboard reads per-app. The harness restriction stops a
well-behaved agent from casually reading your clipboard; it doesn't stop
a determined or compromised one.

## iPhone / Universal Clipboard

If Handoff is enabled and your iPhone and Mac are signed into the same
Apple ID, copying text on your iPhone makes it available to the Mac's
clipboard — and clip-hist records it like any other copy, as long as the
Mac is awake and the iPhone is nearby. iOS only offers a copied item to
other devices for about 2 minutes after you copy it, so paste (or let
clip-hist pick it up) promptly.

## Customizing

- **Picker key**: default is Ctrl+H. Rebind it persistently with:

  ```sh
  clip-hist key ctrl-k   # or: clip-hist key ^K
  ```

  This takes effect in new shells (or run `exec zsh`). For a one-off,
  per-shell override without touching the saved config, set `CLIPHIST_KEY`
  (e.g. `export CLIPHIST_KEY='^K'`) before the `clip-hist.zsh` source line
  runs.

  Note on Ctrl+H specifically: in some terminal configurations Ctrl+H is
  bound to backspace. Default macOS Terminal and iTerm2 send DEL (not
  Ctrl+H) for the backspace key, so Ctrl+H is normally free — but if
  you've customized your terminal or shell to send Ctrl+H for backspace,
  rebind clip-hist off of it.

- **Data directory**: `CLIPHIST_DATA_DIR` is a per-invocation override for
  the CLI and a directly-executed watcher binary — useful for testing and
  scripting. The installed launchd watcher always uses the fixed default
  `~/.local/share/clip-hist`; relocating the store for the installed watcher
  is not supported in v1.

## Uninstall

```sh
./uninstall.sh
```

Unloads the launchd agent, removes the installed binaries and the
`~/.zshrc` source line, and optionally deletes your clipboard history
(you'll be prompted).

## Development

![CI](https://github.com/mobilerajs/clip-hist/actions/workflows/ci.yml/badge.svg)

Tests live in `tests/`, one file per area, each a standalone shell script
with no test framework — run any of them directly:

```sh
tests/test_list.sh
```

**CI-safe** (run on every push via `.github/workflows/ci.yml`, on
macOS — no live clipboard or GUI interaction):

- `test_retention.sh`, `test_list.sh`, `test_pins.sh`, `test_ignore.sh`,
  `test_secrets_cli.sh`, `test_settings.sh` — CLI behavior against a
  temp `CLIPHIST_DATA_DIR`, and the headless parts of the Ctrl+S settings
  helpers

**Local-only** (never run in CI — each touches the real system clipboard
and/or steals window focus to change the frontmost app, which a CI runner
can't do safely or reproducibly):

- `test_misc.sh` — pause/resume, key rebinding, and `clip-hist copy`,
  which writes to the live pasteboard
- `test_watcher.sh`, `test_watcher_app.sh`, `test_watcher_corrupt.sh`,
  `test_watcher_privacy.sh` — exercise the compiled watcher binary
  against the live clipboard, some briefly activating another app
  (e.g. Finder) to test source-app attribution
- `conceal.swift` — helper the watcher tests compile to simulate a
  password-manager-style concealed clipboard write; not a test itself

Run the full local suite (including the ones CI skips) before sending a
PR:

```sh
for t in tests/test_*.sh; do "$t" || echo "FAILED: $t"; done
```

CI also runs `shellcheck -S warning` over `bin/clip-hist`, `install.sh`,
`uninstall.sh`, and `tests/*.sh`, a `zsh -n` syntax check of
`shell/clip-hist.zsh`, and compiles `watcher/main.swift`.

## License

MIT — see [LICENSE](LICENSE).
