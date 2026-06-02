#!/usr/bin/env bash
set -euo pipefail

APP_PATH=""
VERSION=""
BUILD_NUMBER=""
APP_NAME="Shining"
BUNDLE_ID="com.fytriht.shining"
SKIP_NOTARIZATION="${SHINING_SKIP_NOTARIZATION:-0}"
SKIP_SIGNING="${SHINING_SKIP_SIGNING:-0}"

print_usage() {
  cat <<EOF
Usage: $(basename "$0") --app path/to/Shining.app --version X.Y.Z --build-number N

Verifies bundle metadata, code signature, hardened runtime, and notarization assessment.

Environment:
  APPLE_TEAM_ID                Optional expected Apple Developer Team ID.
  SHINING_SKIP_SIGNING=1       Skip codesign verification for local unsigned dry runs.
  SHINING_SKIP_NOTARIZATION=1  Skip Gatekeeper assessment for local dry runs.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --app)
      APP_PATH="${2:-}"
      shift 2
      ;;
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

INFO_PLIST="$APP_PATH/Contents/Info.plist"
APP_BINARY="$APP_PATH/Contents/MacOS/$APP_NAME"

if [[ ! -d "$APP_PATH" ]]; then
  echo "error: app bundle not found at $APP_PATH" >&2
  exit 1
fi

if [[ ! -f "$INFO_PLIST" ]]; then
  echo "error: Info.plist not found at $INFO_PLIST" >&2
  exit 1
fi

if [[ ! -x "$APP_BINARY" ]]; then
  echo "error: app executable not found at $APP_BINARY" >&2
  exit 1
fi

if [[ ! "$VERSION" =~ ^[0-9]+[.][0-9]+[.][0-9]+$ ]]; then
  echo "error: --version must match X.Y.Z" >&2
  exit 1
fi

if [[ ! "$BUILD_NUMBER" =~ ^[0-9]+$ ]]; then
  echo "error: --build-number must be a positive integer" >&2
  exit 1
fi

actual_bundle_id="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$INFO_PLIST")"
actual_version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$INFO_PLIST")"
actual_build="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$INFO_PLIST")"
actual_executable="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$INFO_PLIST")"

if [[ "$actual_bundle_id" != "$BUNDLE_ID" ]]; then
  echo "error: expected CFBundleIdentifier=$BUNDLE_ID, got $actual_bundle_id" >&2
  exit 1
fi

if [[ "$actual_version" != "$VERSION" ]]; then
  echo "error: expected CFBundleShortVersionString=$VERSION, got $actual_version" >&2
  exit 1
fi

if [[ "$actual_build" != "$BUILD_NUMBER" ]]; then
  echo "error: expected CFBundleVersion=$BUILD_NUMBER, got $actual_build" >&2
  exit 1
fi

if [[ "$actual_executable" != "$APP_NAME" ]]; then
  echo "error: expected CFBundleExecutable=$APP_NAME, got $actual_executable" >&2
  exit 1
fi

if [[ "$SKIP_SIGNING" == "1" ]]; then
  echo "Skipping codesign verification because SHINING_SKIP_SIGNING=1."
else
  codesign --verify --deep --strict --verbose=4 "$APP_PATH"

  signing_details="$(codesign -dvvv "$APP_PATH" 2>&1)"
  if [[ "$signing_details" != *"Authority=Developer ID Application"* ]]; then
    echo "error: app is not signed with a Developer ID Application identity." >&2
    echo "$signing_details" >&2
    exit 1
  fi

  if [[ "$signing_details" != *"runtime"* ]]; then
    echo "error: hardened runtime is not enabled on the app signature." >&2
    echo "$signing_details" >&2
    exit 1
  fi

  if [[ -n "${APPLE_TEAM_ID:-}" && "$signing_details" != *"TeamIdentifier=$APPLE_TEAM_ID"* ]]; then
    echo "error: app TeamIdentifier does not match APPLE_TEAM_ID=$APPLE_TEAM_ID." >&2
    echo "$signing_details" >&2
    exit 1
  fi

  entitlements="$(codesign -d --entitlements :- "$APP_PATH" 2>&1 || true)"
  if [[ "$entitlements" == *"com.apple.security.get-task-allow"* ]]; then
    echo "error: release signature must not include com.apple.security.get-task-allow." >&2
    echo "$entitlements" >&2
    exit 1
  fi
fi

if [[ "$SKIP_NOTARIZATION" == "1" ]]; then
  echo "Skipping Gatekeeper assessment because SHINING_SKIP_NOTARIZATION=1."
else
  xcrun stapler validate "$APP_PATH"
  spctl --assess --type execute --verbose=4 "$APP_PATH"
fi

echo "Verified $APP_PATH"
