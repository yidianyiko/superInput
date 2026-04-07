#!/bin/zsh

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="SlashVibe.app"
APP_PATH="$ROOT_DIR/dist/$APP_NAME"
RELEASE_DIR="$ROOT_DIR/release"
STAMP="$(date +%Y%m%d-%H%M%S)"
ZIP_PATH="$RELEASE_DIR/SlashVibe-$STAMP.zip"

cd "$ROOT_DIR"

"$ROOT_DIR/Scripts/build_app_bundle.sh" release

mkdir -p "$RELEASE_DIR"
rm -f "$ZIP_PATH"

ditto -c -k --sequesterRsrc --keepParent "$APP_PATH" "$ZIP_PATH"

echo "Release archive created at:"
echo "  $ZIP_PATH"
