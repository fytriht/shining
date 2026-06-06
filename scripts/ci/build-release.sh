#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
APP_NAME="Shining"
BUNDLE_ID="com.fytriht.shining"
MIN_SYSTEM_VERSION="14.0"
DIST_DIR="$ROOT_DIR/dist/release"
APP_BUNDLE="$DIST_DIR/$APP_NAME.app"
APP_CONTENTS="$APP_BUNDLE/Contents"
APP_MACOS="$APP_CONTENTS/MacOS"
APP_RESOURCES="$APP_CONTENTS/Resources"
APP_BINARY="$APP_MACOS/$APP_NAME"
INFO_PLIST="$APP_CONTENTS/Info.plist"
VERSION=""
BUILD_NUMBER=""
SKIP_SIGNING="${SHINING_SKIP_SIGNING:-0}"

print_usage() {
  cat <<EOF
Usage: $(basename "$0") --version X.Y.Z --build-number N

Builds the Release app bundle into dist/release.

Environment:
  CODESIGN_IDENTITY          Developer ID Application identity for signed builds.
  SHINING_RELEASE_KEYCHAIN   Optional keychain path passed to codesign.
  SHINING_SKIP_SIGNING=1     Build locally without code signing.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --version)
      VERSION="${2:-}"
      shift 2
      ;;
    --build-number)
      BUILD_NUMBER="${2:-}"
      shift 2
      ;;
    -h|--help)
      print_usage
      exit 0
      ;;
    *)
      echo "error: unknown argument: $1" >&2
      print_usage >&2
      exit 1
      ;;
  esac
done

if [[ ! "$VERSION" =~ ^[0-9]+[.][0-9]+[.][0-9]+$ ]]; then
  echo "error: --version must match X.Y.Z" >&2
  exit 1
fi

if [[ ! "$BUILD_NUMBER" =~ ^[0-9]+$ ]]; then
  echo "error: --build-number must be a positive integer" >&2
  exit 1
fi

if ! command -v swift >/dev/null 2>&1; then
  echo "error: swift is not available. Install Xcode and select it with xcode-select." >&2
  exit 1
fi

mkdir -p \
  "$DIST_DIR" \
  "$ROOT_DIR/.build/module-cache" \
  "$ROOT_DIR/.build/module-cache-cc" \
  "$ROOT_DIR/.cache" \
  "$ROOT_DIR/.home" \
  "$ROOT_DIR/.tmp"
rm -rf "$APP_BUNDLE"

cd "$ROOT_DIR"
TMPDIR="$ROOT_DIR/.tmp" swift build -c release --product "$APP_NAME"
BUILD_BINARY="$(TMPDIR="$ROOT_DIR/.tmp" swift build -c release --show-bin-path)/$APP_NAME"

if [[ ! -x "$BUILD_BINARY" ]]; then
  echo "error: release binary was not produced at $BUILD_BINARY" >&2
  exit 1
fi

mkdir -p "$APP_MACOS" "$APP_RESOURCES"
ditto "$BUILD_BINARY" "$APP_BINARY"
chmod +x "$APP_BINARY"

if [[ -f "$ROOT_DIR/Resources/AppIcon.icns" ]]; then
  ditto "$ROOT_DIR/Resources/AppIcon.icns" "$APP_RESOURCES/AppIcon.icns"
fi

cat > "$INFO_PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "https://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key>
  <string>en</string>
  <key>CFBundleDisplayName</key>
  <string>$APP_NAME</string>
  <key>CFBundleExecutable</key>
  <string>$APP_NAME</string>
  <key>CFBundleIconFile</key>
  <string>AppIcon</string>
  <key>CFBundleIdentifier</key>
  <string>$BUNDLE_ID</string>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>CFBundleName</key>
  <string>$APP_NAME</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>$VERSION</string>
  <key>CFBundleVersion</key>
  <string>$BUILD_NUMBER</string>
  <key>LSMinimumSystemVersion</key>
  <string>$MIN_SYSTEM_VERSION</string>
  <key>NSHighResolutionCapable</key>
  <true/>
  <key>NSPrincipalClass</key>
  <string>NSApplication</string>
</dict>
</plist>
PLIST

plutil -lint "$INFO_PLIST"

if [[ "$SKIP_SIGNING" == "1" ]]; then
  echo "Skipping code signing because SHINING_SKIP_SIGNING=1."
else
  : "${CODESIGN_IDENTITY:?CODESIGN_IDENTITY is required unless SHINING_SKIP_SIGNING=1}"

  CODESIGN_ARGS=(
    --force
    --options runtime
    --timestamp
    --sign "$CODESIGN_IDENTITY"
  )

  if [[ -n "${SHINING_RELEASE_KEYCHAIN:-}" ]]; then
    CODESIGN_ARGS+=(--keychain "$SHINING_RELEASE_KEYCHAIN")
  fi

  codesign "${CODESIGN_ARGS[@]}" "$APP_BUNDLE"
  codesign --verify --deep --strict --verbose=4 "$APP_BUNDLE"
fi

echo "Built $APP_BUNDLE"
