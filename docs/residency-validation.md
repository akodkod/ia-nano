# Resident editor validation

Measured locally on 2026-11-20 with release optimization.

| Measurement | Samples | Median | p95 |
| --- | ---: | ---: | ---: |
| Previous executable, repeated fresh launches | 30 after one initial launch | 136.1 ms | 194.1 ms |
| Resident host, real client against optimized AppKit XCTest harness | 30 after one initial request | 35.7 ms | 51.4 ms |

Standalone cold resident launches: 160.3 ms and 175.6 ms. The previous timer began at GUI process entry; the new timer begins at client entry. Neither includes pre-entry executable loading or measures screen presentation. The packaged GUI keyboard benchmark was interrupted by focus/reopen behavior, so its partial warm samples are not used as a 30-run result.

Warm samples (ms): 29.6, 33.3, 49.0, 36.4, 36.5, 38.4, 51.2, 62.1, 30.8, 34.5, 23.4, 25.5, 30.7, 41.9, 35.9, 29.8, 41.4, 41.1, 51.4, 33.5, 27.5, 35.5, 32.7, 45.1, 23.9, 32.2, 38.3, 40.1, 41.5, 25.2.

## Automated checks

- Existing document, highlighting, indentation, backtick, and accent tests.
- Framing fragmentation, oversized/truncated frames, Unicode and binary data, chunking, socket disconnects, lock exclusivity, stale sockets, and endpoint isolation.
- Eight racing GUI startups and eight independent simultaneous socket sessions.
- Protocol/build mismatch rejection, active incompatible-host refusal, idle incompatible-host replacement, and crash diagnostics with no replay.
- Multi-session quit with a conflicting file; successful files close while the conflict retains text and prevents termination.
- Quit waits for output acknowledgment; failed acknowledgment retains editable text and cancels termination.
- Completed editor controllers release after AppKit's autorelease cycle; pending highlighting is cancelled and undo state is discarded.
- Disconnected output buffers recover through Save As.
- Legacy installation migration/protection, resident idle control, update refusal, rollback, and unrelated-destination protection.
- Client linkage inspected with `otool -L`: no AppKit or Tree-sitter dependency.

## Packaged-app checks performed

- Cmd+W returned the exact Unicode pipe bytes and released its waiting client.
- A closed stdout reader produced a delivery diagnostic, retained editable text, and displayed the persistent disconnected notice.
- The native Save As dialog recovered that buffer to a temporary file; its Unicode and newline bytes matched exactly.

## Interactive follow-up

`script/ui_smoke.py` provides the existing terminal file/pipe/cancel/concurrent workflow. Also verify on the normal desktop:

1. Close all editors; Dock/menu disappear. Open Settings while editing, close the last editor, and confirm Settings keeps the app visible. Close Settings and confirm idle hiding.
2. Finder/Dock reopen activates the active editor or creates an empty one. Internal `--background` startup must create no window or steal focus.
3. Interrupt a waiting terminal, edit the retained buffer, use Save As, and verify its bytes. Try closing before saving and confirm explicit discard is required.
4. Break stdout, finish editing, and confirm a persistent disconnected notice and recoverable text.
5. Change the accent and verify all editors update. Exercise menu routing with multiple windows.
6. Cmd+Q, then launch again and confirm a fresh host. Check focus/visibility and screen presentation by eye; window-ready timings cannot prove these.

The full packaged-GUI focus sequence and the two opt-in keyboard-driven integration tests remain manual follow-up; they are not claimed as passed by the harness.
