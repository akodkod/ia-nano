#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MODE="${1:-run}"
case "$MODE" in run|--verify|--debug|--logs|--telemetry) ;; *) echo "Usage: $0 [--verify|--debug|--logs|--telemetry]" >&2; exit 2 ;; esac
# Only stop the previous development launch, never callers' editor sessions.
PID_FILE="$ROOT_DIR/.build/development.pid"
if [ -f "$PID_FILE" ]; then
    PREVIOUS_PID="$(cat "$PID_FILE")"
    PREVIOUS_COMMAND="$(ps -p "$PREVIOUS_PID" -o command= || true)"
    if [[ "$PREVIOUS_COMMAND" == "$ROOT_DIR/dist/iA Nano.app/Contents/MacOS/ia-nano"* ]]; then
        echo "A development editor is still open. Close it before rebuilding." >&2
        exit 2
    fi
fi
APP="$("$ROOT_DIR/script/package.sh" debug)"
if [ "$MODE" = --debug ]; then exec lldb -- "$APP/Contents/MacOS/ia-nano"; fi
/usr/bin/open -n "$APP"
sleep 1
pgrep -f "^$APP/Contents/MacOS/ia-nano" | tail -1 > "$PID_FILE" || true
case "$MODE" in
    --verify) test -s "$PID_FILE" ;;
    --logs|--telemetry) exec /usr/bin/log stream --info --style compact --predicate 'process == "ia-nano"' ;;
esac
