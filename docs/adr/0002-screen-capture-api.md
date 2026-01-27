# ADR 0002: ScreenCaptureKit の採用

## Status

Accepted

## Context

macOS でスクリーンショットを撮影する方法として複数の選択肢がある。

選択肢:
1. `CGWindowListCreateImage` - 古い API、macOS 10.5+
2. `screencapture` コマンド - シェル経由、制御が難しい
3. ScreenCaptureKit - macOS 12.3+ の新しい API

## Decision

ScreenCaptureKit を採用する。

理由:
- Apple が推奨する最新の API
- 非同期 API で Swift Concurrency と相性が良い
- マルチディスプレイ対応が容易
- 権限管理が明確（画面収録の許可）

## Consequences

### Positive
- `async/await` で自然に書ける
- `SCStreamConfiguration` で細かい制御が可能（解像度、カーソル表示など）
- `SCScreenshotManager.captureImage` で簡潔にキャプチャできる

### Negative
- macOS 12.3+ が必須（実際には macOS 15+ をターゲットにしているので問題なし）
- `SCShareableContent` は Sendable ではないため、Swift 6 の strict concurrency で `@preconcurrency import` が必要

### Implementation Notes

```swift
@preconcurrency import ScreenCaptureKit

let content = try await SCShareableContent.current
let filter = SCContentFilter(display: display, excludingWindows: [])
let config = SCStreamConfiguration()
config.sourceRect = selection.rect
config.width = Int(selection.rect.width) * scaleFactor
config.height = Int(selection.rect.height) * scaleFactor

let image = try await SCScreenshotManager.captureImage(
    contentFilter: filter,
    configuration: config
)
```
