# ADR 0004: Retina ディスプレイ対応（@2x）

## Status

Accepted

## Context

Retina ディスプレイ（HiDPI）環境では、論理ピクセルと物理ピクセルが異なる。例えば、@2x ディスプレイでは 100x100 の論理サイズが 200x200 の物理ピクセルになる。

問題:
- キャプチャ時に適切な解像度で取得する必要がある
- 保存時にファイル名で解像度を明示する必要がある
- エディタ表示時に適切なサイズで表示する必要がある

## Decision

1. `NSScreen.backingScaleFactor` を使用してスケールファクターを取得
2. キャプチャ時にスケールファクターに応じたピクセル数でキャプチャ
3. `NSImage` の `size` プロパティは論理サイズを維持
4. ファイル保存時に `@2x` サフィックスをファイル名に付加

## Consequences

### Positive
- Retina 環境で高解像度のスクリーンショットが得られる
- ファイル名から解像度が明確に分かる
- macOS 標準の命名規則に従っている

### Negative
- 非 Retina 環境との互換性を考慮する必要がある
- ファイルサイズが大きくなる

### Implementation Notes

#### Screenshot モデル
```swift
struct Screenshot: Sendable {
    let image: NSImage
    let scaleFactor: CGFloat

    var isRetina: Bool {
        scaleFactor > 1.0
    }
}
```

#### キャプチャ時
```swift
let scaleFactor = screen.backingScaleFactor
config.width = Int(selection.rect.width) * Int(scaleFactor)
config.height = Int(selection.rect.height) * Int(scaleFactor)

// NSImage のサイズは論理サイズを維持
let nsImage = NSImage(cgImage: image, size: NSSize(width: selection.rect.width, height: selection.rect.height))
```

#### 保存時
```swift
let scaleSuffix = screenshot.isRetina ? "@2x" : ""
let fullFilename = "\(baseName)\(scaleSuffix)"
// → "ShotShot_2024-01-27_12-00-00@2x.png"
```
