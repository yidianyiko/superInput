#!/bin/zsh

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_CONFIG="${1:-debug}"
APP_NAME="SlashVibe.app"
APP_DIR="$ROOT_DIR/dist/$APP_NAME"
INSTALL_APP_DIR="${INSTALL_APP_DIR:-$ROOT_DIR/../$APP_NAME}"
EXECUTABLE_NAME="SpeechBarApp"
BUNDLE_ID="com.slashvibe.desktop.local"
DEFAULT_SIGNING_IDENTITY="SpeechBar Local Code Sign 2026"
SIGNING_IDENTITY="${SIGNING_IDENTITY:-$DEFAULT_SIGNING_IDENTITY}"

cd "$ROOT_DIR"

swift build -c "$BUILD_CONFIG" --product "$EXECUTABLE_NAME"

rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"

cp ".build/$BUILD_CONFIG/$EXECUTABLE_NAME" "$APP_DIR/Contents/MacOS/$EXECUTABLE_NAME"
chmod +x "$APP_DIR/Contents/MacOS/$EXECUTABLE_NAME"
cp "$ROOT_DIR/Config/Info.plist" "$APP_DIR/Contents/Info.plist"
if [[ -d "$ROOT_DIR/Resources" ]]; then
    rsync -a "$ROOT_DIR/Resources/" "$APP_DIR/Contents/Resources/"
fi

if ! security find-identity -v -p codesigning | grep -F "\"$SIGNING_IDENTITY\"" >/dev/null; then
    echo "Signing identity not found: $SIGNING_IDENTITY" >&2
    echo "Create it first with:" >&2
    echo "  $ROOT_DIR/Scripts/create_local_signing_identity.sh" >&2
    exit 1
fi

codesign --force --deep --sign "$SIGNING_IDENTITY" --identifier "$BUNDLE_ID" "$APP_DIR"

rm -rf "$INSTALL_APP_DIR"
mkdir -p "$INSTALL_APP_DIR"
rsync -a --delete "$APP_DIR/" "$INSTALL_APP_DIR/"

echo "App bundle created at:"
echo "  $APP_DIR"
echo "Installed copy updated at:"
echo "  $INSTALL_APP_DIR"
echo "Signed with:"
echo "  $SIGNING_IDENTITY"
echo
echo "To launch it:"
echo "  open \"$INSTALL_APP_DIR\""
