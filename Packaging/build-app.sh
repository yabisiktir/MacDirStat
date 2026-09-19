#!/usr/bin/env bash
#
# Builds MacDirStat as a distributable .app bundle.
#
#   ./Packaging/build-app.sh            # release build -> dist/MacDirStat.app
#   ./Packaging/build-app.sh --open     # also launch the app when done
#   VERSION=1.2.0 ./Packaging/build-app.sh
#
set -euo pipefail

# Resolve paths relative to the repo root (parent of this script's dir).
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$ROOT_DIR"

APP_NAME="MacDirStat"
VERSION="${VERSION:-1.0.0}"
DIST_DIR="$ROOT_DIR/dist"
APP_BUNDLE="$DIST_DIR/$APP_NAME.app"
CONFIG="release"

echo "==> Building $APP_NAME ($CONFIG, v$VERSION)"
swift build -c "$CONFIG"

BIN_PATH="$(swift build -c "$CONFIG" --show-bin-path)/$APP_NAME"
if [[ ! -x "$BIN_PATH" ]]; then
	echo "error: built executable not found at $BIN_PATH" >&2
	exit 1
fi

echo "==> Assembling $APP_BUNDLE"
rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

# Binary
cp "$BIN_PATH" "$APP_BUNDLE/Contents/MacOS/$APP_NAME"

# Info.plist (substitute version placeholders)
sed "s/__VERSION__/$VERSION/g" "$SCRIPT_DIR/Info.plist" \
	> "$APP_BUNDLE/Contents/Info.plist"

# Icon
cp "$SCRIPT_DIR/AppIcon.icns" "$APP_BUNDLE/Contents/Resources/AppIcon.icns"

# PkgInfo (optional but conventional)
printf 'APPL????' > "$APP_BUNDLE/Contents/PkgInfo"

# Ad-hoc code signature so the app runs locally without "damaged" warnings.
# Replace `-` with a Developer ID identity for distribution/notarization.
echo "==> Code signing (ad-hoc)"
codesign --force --deep --sign - "$APP_BUNDLE"

echo "==> Done: $APP_BUNDLE"

if [[ "${1:-}" == "--open" ]]; then
	open "$APP_BUNDLE"
fi
