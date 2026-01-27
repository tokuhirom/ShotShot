# ADR 0003: Swift 6 と Strict Concurrency の採用

## Status

Accepted

## Context

Swift 6 では strict concurrency checking がデフォルトで有効になり、データ競合を防ぐための厳格なチェックが行われる。

選択肢:
1. Swift 5 モードで開発し、警告を無視
2. Swift 6 モードで開発し、strict concurrency に準拠

## Decision

Swift 6 モードで開発し、`SWIFT_STRICT_CONCURRENCY = complete` を設定する。

## Consequences

### Positive
- コンパイル時にデータ競合を検出できる
- 将来のメンテナンスが容易
- 安全な並行処理コードが強制される

### Negative
- 一部のフレームワーク（ScreenCaptureKit など）が Sendable に準拠していないため、`@preconcurrency import` が必要
- UI 関連のコードは `@MainActor` で明示的にマークする必要がある

### Implementation Notes

#### @MainActor の使用
UI を操作するクラスは `@MainActor` でマークする:

```swift
@MainActor
final class CaptureManager {
    private var overlayWindows: [NSWindow] = []
    // ...
}
```

#### @preconcurrency import
Sendable でない型を扱う場合:

```swift
@preconcurrency import ScreenCaptureKit
```

#### nonisolated メソッド
actor 境界を越える必要がある場合:

```swift
nonisolated private func checkPermission() async -> Bool {
    do {
        _ = try await SCShareableContent.current
        return true
    } catch {
        return false
    }
}
```
