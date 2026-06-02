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
```

## Notes

Shining is currently built for local development. It does not include App Store sandboxing, signing, notarization, sync, login items, search, or a menu bar icon.
