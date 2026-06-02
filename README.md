# Shining

Shining is a small macOS app for capturing ideas without breaking your workflow.

Press `Command + Option + Enter`, type a quick thought, then save it with the button or `Command + Enter`. The capture window closes, and your note is appended to a local editable idea file.

## Features

- Global hotkey: `Command + Option + Enter`
- Fast 400 x 300 capture window
- Multi-line text input
- Save with `Command + Enter`
- Ideas are appended with timestamps
- Main editor window for reviewing and editing saved ideas
- Local persistence in Application Support
- Native macOS app icon

## Requirements

- macOS 14 or later
- Xcode command line tools
- Swift 6 compatible toolchain

## Run

```bash
./script/build_and_run.sh
```

The script builds a local app bundle at:

```text
dist/Shining.app
```

To build and verify that the app starts:

```bash
./script/build_and_run.sh --verify
```

## Test

```bash
swift test
```

## Release

Shining publishes Developer ID releases from GitHub Actions. Pushing a release tag
builds, signs, notarizes, staples, packages, and publishes the app to GitHub
Releases.

Release tags must match one of these formats:

```text
vX.Y.Z
vX.Y.Z-beta.N
vX.Y.Z-rc.N
```

Required GitHub Actions secrets:

```text
APPLE_TEAM_ID
APPLE_DEVELOPER_ID_CERTIFICATE_BASE64
APPLE_DEVELOPER_ID_CERTIFICATE_PASSWORD
APPLE_KEYCHAIN_PASSWORD
APP_STORE_CONNECT_API_KEY_ID
APP_STORE_CONNECT_API_ISSUER_ID
APP_STORE_CONNECT_API_KEY_P8
```

To publish a release:

```bash
git tag v1.0.0
git push origin v1.0.0
```

The release workflow can also be run manually with `workflow_dispatch`. Set
`publish=false` to build, sign, notarize, and upload workflow artifacts without
creating a GitHub Release.

For a local unsigned dry run:

```bash
SHINING_SKIP_SIGNING=1 scripts/ci/build-release.sh --version 0.0.0 --build-number 1
SHINING_SKIP_SIGNING=1 SHINING_SKIP_NOTARIZATION=1 scripts/ci/verify-release.sh --app dist/release/Shining.app --version 0.0.0 --build-number 1
SHINING_SKIP_SIGNING=1 scripts/ci/package-release.sh --app dist/release/Shining.app --version 0.0.0
```

Release assets are written under `dist/release`:

```text
Shining-<version>.dmg
Shining-<version>.zip
Shining-<version>.sha256
```

## Data Location

Saved ideas are stored at:

```text
~/Library/Application Support/Shining/ideas.md
```

Each capture is appended like this:

```markdown
## yyyy-MM-dd HH:mm

Your idea
```

## Project Structure

```text
Sources/Shining        macOS app, windows, hotkey, views
Sources/ShiningCore    idea formatting and persistence
Tests/ShiningTests     unit tests
Resources              app icon assets
script                 build and run scripts
scripts/ci             release build, signing, notarization, and packaging
```

## Notes

Shining is distributed outside the Mac App Store with Developer ID signing and
notarization. It does not include App Store sandboxing, sync, login items,
search, or a menu bar icon.
