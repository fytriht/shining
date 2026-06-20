#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-run}"
APP_NAME="Shining"
BUNDLE_ID="com.fytriht.shining"
MIN_SYSTEM_VERSION="26.0"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"
APP_BUNDLE="$DIST_DIR/$APP_NAME.app"
APP_CONTENTS="$APP_BUNDLE/Contents"
APP_MACOS="$APP_CONTENTS/MacOS"
APP_RESOURCES="$APP_CONTENTS/Resources"
APP_BINARY="$APP_MACOS/$APP_NAME"
INFO_PLIST="$APP_CONTENTS/Info.plist"

find_developer_id_identity() {
  security find-identity -v -p codesigning 2>/dev/null |
    awk '/"Developer ID Application: / {print $2; exit}'
}

pkill -x "$APP_NAME" >/dev/null 2>&1 || true

swift build
BUILD_BINARY="$(swift build --show-bin-path)/$APP_NAME"

rm -rf "$APP_BUNDLE"
mkdir -p "$APP_MACOS" "$APP_RESOURCES"
cp "$BUILD_BINARY" "$APP_BINARY"
chmod +x "$APP_BINARY"

if [[ -f "$ROOT_DIR/Resources/AppIcon.icns" ]]; then
  cp "$ROOT_DIR/Resources/AppIcon.icns" "$APP_RESOURCES/AppIcon.icns"
fi

cat >"$INFO_PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key>
  <string>$APP_NAME</string>
  <key>CFBundleIconFile</key>
  <string>AppIcon</string>
  <key>CFBundleIdentifier</key>
  <string>$BUNDLE_ID</string>
  <key>CFBundleName</key>
  <string>$APP_NAME</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>LSMinimumSystemVersion</key>
  <string>$MIN_SYSTEM_VERSION</string>
  <key>NSHighResolutionCapable</key>
  <true/>
  <key>NSPrincipalClass</key>
  <string>NSApplication</string>
</dict>
</plist>
PLIST

plutil -lint "$INFO_PLIST" >/dev/null

CODESIGN_IDENTITY="${SHINING_CODESIGN_IDENTITY:-${CODESIGN_IDENTITY:-}}"
if [[ -z "$CODESIGN_IDENTITY" ]]; then
  CODESIGN_IDENTITY="$(find_developer_id_identity || true)"
fi

if [[ -n "$CODESIGN_IDENTITY" && "$CODESIGN_IDENTITY" != "-" ]]; then
  CODESIGN_ARGS=(
    --force
    --deep
    --options runtime
    --timestamp=none
    --sign "$CODESIGN_IDENTITY"
  )

  if [[ -n "${SHINING_RELEASE_KEYCHAIN:-}" ]]; then
    CODESIGN_ARGS+=(--keychain "$SHINING_RELEASE_KEYCHAIN")
  fi

  codesign "${CODESIGN_ARGS[@]}" "$APP_BUNDLE" >/dev/null
else
  codesign --force --deep --sign - "$APP_BUNDLE" >/dev/null
fi

open_app() {
  /usr/bin/open -n "$APP_BUNDLE"
}

case "$MODE" in
  run)
    open_app
    ;;
  --debug|debug)
    lldb -- "$APP_BINARY"
    ;;
  --logs|logs)
    open_app
    /usr/bin/log stream --info --style compact --predicate "process == \"$APP_NAME\""
    ;;
  --verify|verify)
    open_app
    sleep 1
    pgrep -x "$APP_NAME" >/dev/null
    ;;
  *)
    echo "usage: $0 [run|--debug|--logs|--verify]" >&2
    exit 2
    ;;
esac
