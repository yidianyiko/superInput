#!/bin/zsh

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_TITLE="${APP_TITLE:-SlashVibe}"
APP_NAME="${APP_NAME:-SlashVibe.app}"
EXECUTABLE_NAME="${EXECUTABLE_NAME:-SpeechBarApp}"
OUT_BASE="${OUT_BASE:-$ROOT_DIR/dist/ui-verify}"
STAMP="$(date +%Y%m%d-%H%M%S)"
RUN_DIR="${OUT_DIR:-$OUT_BASE/$STAMP}"
LATEST_LINK="$OUT_BASE/latest"

APP_PATH="${APP_PATH:-$ROOT_DIR/../$APP_NAME}"
if [[ ! -d "$APP_PATH" && -d "$ROOT_DIR/dist/$APP_NAME" ]]; then
    APP_PATH="$ROOT_DIR/dist/$APP_NAME"
fi

if [[ ! -d "$APP_PATH" ]]; then
    echo "App bundle not found, building one first..." >&2
    "$ROOT_DIR/Scripts/build_app_bundle.sh"
    APP_PATH="$ROOT_DIR/../$APP_NAME"
fi

APP_PATH="$(cd "$(dirname "$APP_PATH")" && pwd)/$(basename "$APP_PATH")"

mkdir -p "$RUN_DIR"

APP_EXECUTABLE="$APP_PATH/Contents/MacOS/$EXECUTABLE_NAME"
LLDB_COMMANDS="$RUN_DIR/lldb-commands.txt"
WINDOW_STATE="$RUN_DIR/window-state.txt"
WINDOW_INFO="$RUN_DIR/window-info.tsv"
WINDOW_CAPTURE="$RUN_DIR/window.png"
FULL_CAPTURE="$RUN_DIR/fullscreen.png"
OCR_OUTPUT="$RUN_DIR/ocr.tsv"
SUMMARY="$RUN_DIR/summary.txt"

echo "App path: $APP_PATH" | tee "$SUMMARY"
echo "Run dir:  $RUN_DIR" | tee -a "$SUMMARY"

open -a "$APP_PATH"

PID=""
for _ in {1..30}; do
    PID="$(
        ps -axo pid=,command= | awk -v target="$APP_EXECUTABLE" '
            {
                pid = $1
                $1 = ""
                sub(/^ +/, "", $0)
                if ($0 == target) {
                    print pid
                    exit
                }
            }
        '
    )"
    if [[ -n "$PID" ]]; then
        break
    fi
    sleep 1
done

if [[ -z "$PID" ]]; then
    echo "Could not find a running $EXECUTABLE_NAME process for $APP_PATH" >&2
    exit 1
fi

echo "PID:      $PID" | tee -a "$SUMMARY"

cat > "$LLDB_COMMANDS" <<EOF
expr -l Swift -- import AppKit
expr -l Swift -- NSApp.activate(ignoringOtherApps: true)
expr -l Swift -- if let window = NSApp.windows.first(where: { \$0.title == "$APP_TITLE" }) { window.makeKeyAndOrderFront(nil); window.orderFrontRegardless() }
expr -l Swift -- NSApp.windows.map { [\$0.title, String(\$0.isVisible), NSStringFromRect(\$0.frame)] }
EOF

if ! lldb -p "$PID" --batch -s "$LLDB_COMMANDS" > "$WINDOW_STATE" 2>&1; then
    echo "LLDB attach failed. Check Developer Tools permission and retry." >&2
    exit 1
fi

WINDOW_ID=""
if swift "$ROOT_DIR/Scripts/ui_window_probe.swift" "$PID" "$APP_TITLE" > "$WINDOW_INFO"; then
    WINDOW_ID="$(awk -F '\t' 'NR == 1 { print $1 }' "$WINDOW_INFO")"
fi

sleep 1

if [[ -n "$WINDOW_ID" ]]; then
    screencapture -x -l "$WINDOW_ID" "$WINDOW_CAPTURE"
    CAPTURE_PATH="$WINDOW_CAPTURE"
else
    screencapture -x "$FULL_CAPTURE"
    CAPTURE_PATH="$FULL_CAPTURE"
fi

swift "$ROOT_DIR/Scripts/ui_window_probe.swift" ocr "$CAPTURE_PATH" > "$OCR_OUTPUT"

ln -sfn "$RUN_DIR" "$LATEST_LINK"

{
    echo "Capture:  $CAPTURE_PATH"
    echo "OCR:      $OCR_OUTPUT"
    echo "Window:   $WINDOW_INFO"
    echo "State:    $WINDOW_STATE"
} | tee -a "$SUMMARY"

echo
echo "Verification artifacts written to $RUN_DIR"
