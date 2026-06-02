# Contributing

Thanks for improving Shining. Keep changes small, clear, and easy to test.

## Setup

```bash
swift test
./script/build_and_run.sh
```

Use `./script/build_and_run.sh` as the main local run command. It builds `dist/Shining.app` and launches it as a real macOS app bundle.

## Development Guidelines

- Keep app lifecycle and window behavior in `Sources/Shining/App`.
- Keep SwiftUI views in `Sources/Shining/Views`.
- Keep reusable idea formatting and persistence logic in `Sources/ShiningCore`.
- Add tests for behavior in `Tests/ShiningTests`.
- Prefer SwiftUI first, and use AppKit only for macOS-specific behavior that SwiftUI does not handle well.
- Do not commit build output from `.build/` or `dist/`.

## Testing

Run tests before submitting changes:

```bash
swift test
```

For UI or lifecycle changes, also run:

```bash
./script/build_and_run.sh --verify
```

Manually check these flows when relevant:

- `Command + Option + Enter` opens the capture window.
- `Command + Enter` saves a non-empty capture.
- Saved text appears in the main editor.
- Edits in the main editor persist after relaunch.
- Closing a non-empty main window asks for confirmation.

## Pull Request Checklist

- The change is focused.
- Tests pass.
- New behavior has tests when practical.
- User-facing behavior is documented if it changed.
- No generated build artifacts are committed.

## Style

Use simple Swift code with clear ownership. Avoid broad refactors unless they directly support the change being made.
