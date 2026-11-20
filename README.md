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
| Cmd+Escape | Cancel without submitting or making additional writes |
| Cmd+Z / Cmd+Shift+Z | Undo / redo |

Cancellation does not revert earlier Cmd+S saves. Escape alone does not discard text. Exit status is `0` for success, `1` for cancellation, and `2` for argument/loading errors. Output mode writes only your text to stdout; diagnostics go to stderr. Save/output errors keep the editor open so text can be recovered.

Drag the empty strip at the top to move the window; drag its edges to resize. The editor follows the system light/dark appearance. Text stays raw: backticks are visible, and syntax colors do not become document formatting. Use `ruby` / `rb` or `ts` / `typescript` after an opening fence. An unfinished fenced block is highlighted through the end of the document. Other languages stay plain.

## File behavior

- UTF-8 only; invalid data is rejected. UTF-8 BOMs are preserved.
- Unedited files round-trip byte-for-byte, including mixed line endings.
- Edited files use the original newline convention (CRLF if present, otherwise CR if present, otherwise LF). New text uses LF. No trailing newline is added or removed automatically.
- Saves resolve symlinks, use an atomic write, and preserve existing POSIX permissions. A changed or deleted file is detected before saving, and an error keeps your buffer open. This check is not a filesystem lock; avoid simultaneous writes to the same file.
- No background autosave. Cancelled edits remain unsaved unless you explicitly saved earlier.
- This is a small prompt editor: no tabs, project sidebar, preview, language server, or persistent background service.

## Local installation

The app is ad-hoc signed for local use, not notarized for distribution. The launcher can be symlinked into a directory on PATH:

```sh
mkdir -p "$HOME/.local/bin"
ln -s "$PWD/bin/ia-nano" "$HOME/.local/bin/ia-nano"
```

Keep the checkout and `dist/iA Nano.app` in place. Alternatively, copy the app wherever you prefer and set `IA_NANO_APP` to its full path before invoking the launcher. Finder launch opens an empty editor; use the terminal launcher when you need returned output.

## Checks

`swift test` covers invocation parsing, UTF-8 and newline round trips, symlink and permission preservation, file conflicts, failure paths, and fenced highlighting with Unicode offsets. Run `python3 script/ui_smoke.py` for an interactive file/pipe/cancellation/concurrency check; follow its printed keyboard instructions. Additional manual checks cover focus, undo, caret rendering, dragging/resizing, and save-error recovery.

The initial Apple Silicon release bundle measured 4.2 MB. Two local launches presented their windows in 127–146 ms after process entry (excluding executable loading). Set `IA_NANO_METRICS=1` to print this timing to stderr. These measurements are not a cold-start guarantee.

An independent project inspired by focused writing tools; not affiliated with iA.
