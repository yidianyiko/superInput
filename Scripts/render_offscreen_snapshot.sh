#!/bin/zsh

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
OUT_BASE="${OUT_BASE:-$ROOT_DIR/dist/offscreen-ui}"
STAMP="$(date +%Y%m%d-%H%M%S)"
RUN_DIR="${OUT_DIR:-$OUT_BASE/$STAMP}"
LATEST_LINK="$OUT_BASE/latest"
OUTPUT_PATH="${OUTPUT_PATH:-$RUN_DIR/home.png}"
OCR_PATH="$RUN_DIR/ocr.tsv"
SUMMARY_PATH="$RUN_DIR/summary.txt"

mkdir -p "$RUN_DIR"

swift build -c debug --product SpeechBarApp >/dev/null

"$ROOT_DIR/.build/debug/SpeechBarApp" \
    --render-home-snapshot "$OUTPUT_PATH" \
    "$@"

swift "$ROOT_DIR/Scripts/ui_window_probe.swift" ocr "$OUTPUT_PATH" > "$OCR_PATH"

{
    echo "Output: $OUTPUT_PATH"
    echo "OCR:    $OCR_PATH"
} > "$SUMMARY_PATH"

ln -sfn "$RUN_DIR" "$LATEST_LINK"

echo "Offscreen snapshot written to:"
echo "  $OUTPUT_PATH"
echo "OCR written to:"
echo "  $OCR_PATH"
