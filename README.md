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

For development, `./script/build_and_run.sh` builds a debug app bundle and opens it. `--verify` also checks that it launched; `--debug`, `--logs`, and `--telemetry` provide debugging entry points. Builds stop the matching idle development host; open editors or settings prevent bundle replacement. The Codex Run action uses this script.

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

`ia-nano FILE` waits for the editor to finish, saving to the same file. `ia-nano -` reads stdin through EOF and writes the edited text to stdout on completion. Without arguments, the editor starts empty and returns its text on stdout. Only one file is accepted per invocation. Each invocation has a lightweight waiting terminal client and its own editing session. A single resident GUI process serves sessions for that app-bundle location; callers keep separate output and exit status.

| Shortcut | Action |
| --- | --- |
| Ctrl+W or Cmd+W | Save/submit and close |
| Cmd+Q | Finish all sessions and genuinely quit; failures keep their editors open |
| Cmd+S | Save file without closing; Save As for an output-only buffer |
| Cmd+Shift+S | Save As |
| Cmd+, | Open Settings |
| Cmd+Escape | Cancel without submitting or making additional writes |
| Cmd+Z / Cmd+Shift+Z | Undo / redo |
| Tab / Shift+Tab | Indent / unindent by two spaces (selected lines supported) |

Cancellation does not revert earlier Cmd+S saves. Escape alone does not discard text. Exit status is `0` for success, `1` for cancellation, and `2` for argument, loading, connection, or stdout-delivery errors. Output mode writes only your text to stdout; diagnostics go to stderr. Save/output errors keep the editor open so text can be recovered.

Open **iA Nano → Settings…** (Cmd+,) to choose the accent color. Each card previews the rounded caret; the selection applies immediately and persists across launches. Blue is the default. Settings can be closed with Cmd+W, Ctrl+W, or Escape without submitting your text.

Drag the empty strip at the top to move the window; drag its edges to resize. The editor follows the system light/dark appearance. Typing a backtick inserts a matching backtick, or wraps selected text. Typing three backticks at the start of a line adds a closing fence on the next line, leaving the caret after the opening fence for a language name. Pasted text stays unchanged. Text stays raw: backticks are visible, and syntax colors do not become document formatting. Use `ruby` / `rb` or `ts` / `typescript` after an opening fence. An unfinished fenced block is highlighted through the end of the document. Other languages stay plain. Enter inside a fenced code block carries the current line’s indentation onto the new line; it does not infer additional indentation from language syntax.

## Residency and recovery

After first use, the GUI stays running. Closing the last editor hides its Dock icon and menu bar, unless Settings is still open. Reopening reuses the host. No login item is installed. Development and installed copies have separate hosts, identified by their canonical bundle locations.

Cmd+W/Ctrl+W finishes only the current editor; Cmd+Escape cancels only that session. Cmd+Q finishes every session and exits only after all saves and output acknowledgments succeed. To stop a host from a script, run `ia-nano --quit-if-idle`: it succeeds if no host exists or the host is idle, and refuses while any editor or settings window is open. `--help` and `--version` never start the GUI.

If a terminal exits or is interrupted, its editor stays open with a persistent disconnected notice. File buffers can still be saved. For output-only buffers, use Cmd+S / Save As or copy the text; closing without saving requires an explicit discard choice. Stdout must be successfully written and acknowledged before an output session closes. Failed delivery leaves the text recoverable. A host crash releases waiting clients with status 2 and a diagnostic; requests are never automatically replayed.

The shell launcher and `IA_NANO_APP` override are unchanged. `Contents/MacOS/ia-nano` is the Foundation-only client; Finder launches `ia-nano-gui`. IPC uses bounded frames and chunked payloads with no document-size cap, owner-only socket directories, verified peer user IDs, and a host-lifetime exclusive lock. An incompatible idle host is replaced; active sessions are never terminated automatically.

## File behavior

- UTF-8 only; invalid data is rejected. UTF-8 BOMs are preserved.
- Unedited files round-trip byte-for-byte, including mixed line endings.
- Edited files use the original newline convention (CRLF if present, otherwise CR if present, otherwise LF). New text uses LF. No trailing newline is added or removed automatically.
- Saves resolve symlinks, use an atomic write, and preserve existing POSIX permissions. A changed or deleted file is detected before saving, and an error keeps your buffer open. This check is not a filesystem lock; avoid simultaneous writes to the same file.
- No background autosave. Cancelled edits remain unsaved unless you explicitly saved earlier.
- This is a small prompt editor: no tabs, project sidebar, preview, language server, or launch-at-login service.

## Local installation

The app is ad-hoc signed for local use, not notarized for distribution. From the project folder:

```sh
./script/package.sh
./script/install.sh
```

The installer copies the app to `~/Applications/iA Nano.app` and the launcher to `~/.local/bin/ia-nano`. It is safe to rerun: updates replace the complete app bundle, so removed files do not linger. The installer stops only the matching idle host; open editors or settings block updates. Older nonresident installations are recognized and must be closed first. The scripts refuse to overwrite unrelated files at either destination and do not edit your shell configuration.

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

Finder launch or Dock reopen activates an existing editor, or opens an empty one if none exists. Use Cmd+S to save a Finder buffer; use the terminal launcher when you need returned output. The installed copy does not depend on keeping the checkout in place.

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

`python3 -m unittest discover -s Tests/Resident -v` exercises real release executables in isolated locations: concurrent startup, independent requests, stale sockets, mismatched protocols/builds, disconnects, and host crashes. Build the release bundle first. Two optional keyboard-driven tests require `IA_NANO_UI_TESTS=1` and macOS Accessibility access.

Swift tests also cover multi-session quit with save conflicts, output acknowledgment/failure, recovery through Save As, framing and binary payloads, and release of completed controllers. See [validation notes](docs/residency-validation.md) for measurements and remaining manual checks.

### Opening performance

`IA_NANO_METRICS=1 ia-nano` reports **cold** or **warm** client-entry-to-window-ready timing on stderr. This includes IPC and window setup, but excludes executable loading before client entry and does not measure pixels appearing on screen. First use still starts AppKit; warm use reuses the resident process.

On this Mac, the prior release measured median **136.1 ms**, p95 **194.1 ms** over 30 repeated launches. The resident release harness measured median **35.7 ms**, p95 **51.4 ms** over 30 warm openings, meeting the <50/<100 ms targets. The harness launches the real release terminal client against the optimized AppKit host code inside XCTest, completes each editor, and verifies the session registry returns to empty. These are different launch conditions, not a screen-presentation comparison. One standalone cold resident launch measured **160.3 ms**.

Reproduce the warm harness with:

```sh
./script/package.sh release
IA_NANO_BENCHMARK=1 swift test -c release --filter testReleaseWarmBenchmark
```

`python3 script/benchmark.py` runs the separate packaged-GUI benchmark with keyboard automation; it requires Accessibility access and stable keyboard focus.

An independent project inspired by focused writing tools; not affiliated with iA.
