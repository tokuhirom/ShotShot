# ShotShot - Project Info for Claude Code

All documentation, commit messages, and code comments must be written in English.

## Build & Run

```bash
# Debug build
./scripts/build.sh debug

# Release build
./scripts/build.sh release

# Run (auto-builds if needed, with log output)
./scripts/run.sh
```

## Debugging

### Crash Logs

macOS crash logs are saved at:
```bash
~/Library/Logs/DiagnosticReports/
```

Show the latest ShotShot crash log:
```bash
cat ~/Library/Logs/DiagnosticReports/$(ls -t ~/Library/Logs/DiagnosticReports/ | grep -i shotshot | head -1)
```

When launched via `./scripts/run.sh`, crash logs are displayed automatically.

### App Logs

Running via `./scripts/run.sh` saves log files to `./logs/`.

`print()` may not produce output in macOS GUI apps. Use `NSLog()` for important logs.

## Tech Stack

- Swift 6 (strict concurrency)
- SwiftUI + AppKit
- ScreenCaptureKit (screen capture & recording)
- AVFoundation (video recording & export)
- macOS 15.0+

## Architecture

```
shotshot/
├── App/             # Entry point, AppDelegate
├── Features/
│   ├── Capture/     # Screen capture, region selection UI
│   ├── Editor/      # Editor window
│   ├── Annotations/ # Arrow, rectangle, text, mosaic tools
│   ├── MenuBar/     # Menu bar integration
│   ├── Recording/   # Screen recording (SCStream + AVAssetWriter)
│   └── Settings/    # Settings view
├── Models/          # Data models
├── Services/        # Clipboard, image export, video export, hotkey
└── Resources/       # Assets, Info.plist
```

## Notes

- `@MainActor` is used extensively. Be careful with Swift 6 concurrency restrictions.
- NSWindow uses `isReleasedWhenClosed = false` for ARC-based lifecycle management.
- NotificationCenter closure-based observers must have their tokens stored and removed.
- Do not subclass NSWindow with custom designated initializers (use composition instead).
- `closeOverlayWindows()` must always be called via `defer` to prevent overlay windows from getting stuck on cancel.

## Tasks

 - [x] Crop feature
 - [x] Color display in dropdown menu color picker
 - [ ] Cmd-S to save image with name
 - [x] Cmd-V to open image from clipboard for editing
 - [x] Cmd-C to copy to clipboard
 - [x] Make select and arrow icons more distinguishable
