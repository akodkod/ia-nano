# iA Nano

A small native macOS editor for terminal prompts and temporary files. Swift + AppKit, with a plain-text NSTextView and Tree-sitter highlighting for Ruby and TypeScript fenced blocks. Requires macOS 14 or later.

## Build and run

Requires Xcode or a Swift toolchain with the macOS SDK. The first build downloads dependencies.

```sh
swift build
swift test
./script/package.sh          # Release app at dist/iA Nano.app
./bin/ia-nano prompt.md
```

For development, `./script/build_and_run.sh` builds a debug app bundle and opens it. `--verify` also checks that it launched; `--debug`, `--logs`, and `--telemetry` provide debugging entry points. Close the previous development editor before rebuilding. The Codex Run action uses this script.

## Use from your terminal

Add this checkout's `bin` directory to PATH, then:

```sh
export EDITOR=ia-nano
export VISUAL=ia-nano

ia-nano prompt.md
printf 'Explain this code' | ia-nano -
response=$(ia-nano)
ia-nano -- -unusual-filename
```

`ia-nano FILE` waits for the editor to finish, saving to the same file. `ia-nano -` reads stdin through EOF and writes the edited text to stdout on completion. Without arguments, the editor starts empty and returns its text on stdout. Only one file is accepted per invocation. Every invocation owns its own process and window, so multiple waiting callers remain independent.

| Shortcut | Action |
| --- | --- |
| Ctrl+W or Cmd+W | Save/submit and close |
| Cmd+Q | Save/submit and quit |
| Cmd+S | Save file without closing |
| Cmd+, | Open Settings |
| Cmd+Escape | Cancel without submitting or making additional writes |
| Cmd+Z / Cmd+Shift+Z | Undo / redo |
| Tab / Shift+Tab | Indent / unindent by two spaces (selected lines supported) |

Cancellation does not revert earlier Cmd+S saves. Escape alone does not discard text. Exit status is `0` for success, `1` for cancellation, and `2` for argument/loading errors. Output mode writes only your text to stdout; diagnostics go to stderr. Save/output errors keep the editor open so text can be recovered.

Open **iA Nano → Settings…** (Cmd+,) to choose the accent color. Each card previews the rounded caret; the selection applies immediately and persists across launches. Blue is the default. Settings can be closed with Cmd+W, Ctrl+W, or Escape without submitting your text.

Drag the empty strip at the top to move the window; drag its edges to resize. The editor follows the system light/dark appearance. Typing a backtick inserts a matching backtick, or wraps selected text. Typing three backticks at the start of a line adds a closing fence on the next line, leaving the caret after the opening fence for a language name. Pasted text stays unchanged. Text stays raw: backticks are visible, and syntax colors do not become document formatting. Use `ruby` / `rb` or `ts` / `typescript` after an opening fence. An unfinished fenced block is highlighted through the end of the document. Other languages stay plain. Enter inside a fenced code block carries the current line’s indentation onto the new line; it does not infer additional indentation from language syntax.

## File behavior

- UTF-8 only; invalid data is rejected. UTF-8 BOMs are preserved.
- Unedited files round-trip byte-for-byte, including mixed line endings.
- Edited files use the original newline convention (CRLF if present, otherwise CR if present, otherwise LF). New text uses LF. No trailing newline is added or removed automatically.
- Saves resolve symlinks, use an atomic write, and preserve existing POSIX permissions. A changed or deleted file is detected before saving, and an error keeps your buffer open. This check is not a filesystem lock; avoid simultaneous writes to the same file.
- No background autosave. Cancelled edits remain unsaved unless you explicitly saved earlier.
- This is a small prompt editor: no tabs, project sidebar, preview, language server, or persistent background service.

## Local installation

The app is ad-hoc signed for local use, not notarized for distribution. From the project folder:

```sh
./script/package.sh
./script/install.sh
```

The installer copies the app to `~/Applications/iA Nano.app` and the launcher to `~/.local/bin/ia-nano`. It is safe to rerun: updates replace the complete app bundle, so removed files do not linger. Close installed editor sessions first. The scripts refuse to overwrite unrelated files at either destination and do not edit your shell configuration.

### zsh

Add these lines to `~/.zshrc`:

```sh
export PATH="$HOME/.local/bin:$PATH"
export IA_NANO_APP="$HOME/Applications/iA Nano.app"
export EDITOR=ia-nano
export VISUAL=ia-nano
```

Reload your shell configuration:

```sh
source ~/.zshrc
```

### fish

Add these lines to `~/.config/fish/config.fish` (create the file if needed):

```fish
fish_add_path --path "$HOME/.local/bin"
set -gx IA_NANO_APP "$HOME/Applications/iA Nano.app"
set -gx EDITOR ia-nano
set -gx VISUAL ia-nano
```

Reload the configuration:

```fish
source ~/.config/fish/config.fish
```

[`fish_add_path`](https://fishshell.com/docs/current/cmds/fish_add_path.html) avoids duplicate PATH entries. `--path` keeps the change in the current shell; the config file reapplies it for future shells.

### Using and updating the installation

You can now launch the app from Finder or use it from your terminal:

```sh
ia-nano notes.md
printf 'Write a prompt' | ia-nano -
```

Finder launch opens an empty editor; use the terminal launcher when you need returned output. The installed copy does not depend on keeping the checkout in place.

To update, close installed iA Nano sessions and rerun:

```sh
./script/package.sh
./script/install.sh
```

### Uninstalling

Close installed iA Nano sessions, then run:

```sh
./script/uninstall.sh
```

It is safe to run repeatedly. Only the installed app and launcher are removed; your documents and saved accent preference remain. Remove the `IA_NANO_APP`, `EDITOR`, and `VISUAL` lines you added to your shell config, or change `EDITOR` and `VISUAL` to another editor. Keep `~/.local/bin` on PATH if you use it for other tools. Open a new shell afterward so old exported values are gone.

For isolated script testing, `IA_NANO_INSTALL_ROOT` overrides the home-directory installation root. Normal installation does not require it.

## Checks

`python3 Tests/Installation/test_install.py` checks repeated installs/uninstalls, updates, rollback, existing launchers, and running-app protection using disposable installation roots.

`swift test` covers invocation parsing, UTF-8 and newline round trips, symlink and permission preservation, file conflicts, failure paths, and fenced highlighting with Unicode offsets. Run `python3 script/ui_smoke.py` for an interactive file/pipe/cancellation/concurrency check; follow its printed keyboard instructions. Additional manual checks cover focus, undo, caret rendering, dragging/resizing, and save-error recovery.

The initial Apple Silicon release bundle measured 4.2 MB. Two local launches presented their windows in 127–146 ms after process entry (excluding executable loading). Set `IA_NANO_METRICS=1` to print this timing to stderr. These measurements are not a cold-start guarantee.

An independent project inspired by focused writing tools; not affiliated with iA.
