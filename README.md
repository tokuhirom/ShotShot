# ShotShot

A screenshot & screen recording tool for macOS. Capture a selected region, annotate with arrows, rectangles, text, and mosaic, or record your screen as MP4/GIF.

![ShotShot](image.png)

## Features

### Screenshot Capture
- **Menu bar app**: Lives in the menu bar (no Dock icon)
- **Global hotkey**: Default `⌃⇧4` to capture (configurable in settings)
- **Timer capture**: 3-second countdown mode via `⌃⇧5`
- **Region selection**: Powered by ScreenCaptureKit
- **Retina support**: Full high-DPI display support

### Scroll Capture (Experimental)
- **Scrolling screenshot**: Capture an entire scrollable area via `⌃⇧7`
- **Automatic detection**: Captures are triggered automatically as you scroll
- **Image stitching**: Overlapping regions are detected and merged into a single image
- **Visual feedback**: Flash effect on each capture, progress indicator with capture count

### Screen Recording
- **Record selected region**: Choose any area of the screen to record via `⌃⇧6`
- **Recording indicator**: Red border with REC badge, elapsed time, and stop button
- **Save as MP4 or GIF**: Choose format in the save dialog
- **Stop recording**: Press Escape, click the stop button, or use the menu bar

### Annotation Tools
- **Select**: Select, move, and resize annotations
- **Crop**: Trim unwanted areas from the image
- **Arrow**: Customizable color and thickness with white outline
- **Rectangle**: Toggle rounded/sharp corners, customizable color and thickness
- **Text**: Adjustable font size and color with white outline
- **Mosaic**: Pixelate selected areas

### Editing
- **Undo/Redo**: Full undo and redo support
- **Persistent settings**: Tool, color, thickness, and font size are restored on next launch

### Output
- **Image export**: PNG format, default location `~/Pictures/ShotShot/`
- **Clipboard copy**: Automatically copies to clipboard on save
- **Video export**: MP4 (H.264) or GIF format

## Keyboard Shortcuts

| Shortcut | Action |
|----------|--------|
| ⌃⇧4 | Take screenshot |
| ⌃⇧5 | Take screenshot with 3s timer |
| ⌃⇧6 | Record screen |
| ⌃⇧7 | Scroll capture |
| ⌘Z | Undo |
| ⇧⌘Z | Redo |
| ⌘S | Save as |
| ⌘C | Copy to clipboard |
| ⌘V | Open image from clipboard |
| Delete | Delete selected annotation |
| Escape | Cancel capture / Stop recording |

## Requirements

- macOS 15.0+
- Xcode 16.0+
- Swift 6

## Installation

### Build

```bash
# Debug build
./scripts/build.sh debug

# Release build
./scripts/build.sh release
```

### Run

```bash
# Launch the latest build (auto-builds if needed)
./scripts/run.sh
```

## Usage

### Screenshots

1. Launch the app — a camera icon appears in the menu bar
2. Press `⌃⇧4` or select "Take Screenshot" from the menu
3. Drag to select the region you want to capture
4. The editor window opens — add annotations as needed
5. Click "Done" to save and copy to clipboard

### Scroll Capture

1. Press `⌃⇧7` or select "Scroll Capture" from the menu
2. Drag to select the region you want to capture
3. Scroll the content — captures are taken automatically
4. Press "Done" or Enter to finish
5. The stitched image opens in the editor

### Screen Recording

1. Press `⌃⇧6` or select "Record Screen" from the menu
2. Drag to select the region you want to record
3. A red border with a REC badge appears around the selected area
4. Press Escape, click the stop button, or select "Stop Recording" from the menu
5. Choose the save location and format (MP4 or GIF)

### Open Image from Clipboard

Press `⌘V` while the editor window is active to open an image from the clipboard in a new window.

### Settings

Select "Settings" from the menu to configure:
- Image save location
- Global hotkey

## Permissions

This app requires the following permission:

- **Screen Recording**: Required for capturing screenshots and recording the screen

You will be prompted to grant access in System Settings on first launch.

## License

MIT License
