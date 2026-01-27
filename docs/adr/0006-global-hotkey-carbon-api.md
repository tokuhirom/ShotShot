# ADR 0006: グローバルホットキーに Carbon API を使用

## Status

Accepted

## Context

グローバルホットキー（アプリがフォアグラウンドでなくても動作するショートカット）を実装する方法を検討した。

選択肢:
1. Carbon Event API (`RegisterEventHotKey`)
2. `CGEventTap` - より低レベルだがアクセシビリティ権限が必要
3. `NSEvent.addGlobalMonitorForEvents` - modifier + key の組み合わせでは制限あり
4. サードパーティライブラリ（HotKey, MASShortcut など）

## Decision

Carbon Event API (`RegisterEventHotKey`) を使用する。

理由:
- 追加の権限（アクセシビリティ）が不要
- シンプルで信頼性が高い
- macOS で長年使われてきた実績がある

## Consequences

### Positive
- 画面収録の権限のみで動作する
- 外部依存なし
- CPU オーバーヘッドが少ない

### Negative
- Carbon API は古い C ベースの API
- Swift から呼び出す際にやや冗長なコードが必要
- `@MainActor` との統合に注意が必要

### Implementation Notes

```swift
import Carbon

@MainActor
final class HotkeyManager {
    private var eventHandler: EventHandlerRef?
    private var hotkeyRef: EventHotKeyRef?

    func register() {
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        let handlerCallback: EventHandlerUPP = { _, event, _ in
            Task { @MainActor in
                HotkeyManager.sharedInstance?.onHotkeyPressed?()
            }
            return noErr
        }

        InstallEventHandler(
            GetApplicationEventTarget(),
            handlerCallback,
            1,
            &eventType,
            nil,
            &eventHandler
        )

        let hotkeyID = EventHotKeyID(signature: OSType(0x53534854), id: 1)
        RegisterEventHotKey(
            keyCode,
            modifiers,
            hotkeyID,
            GetApplicationEventTarget(),
            0,
            &hotkeyRef
        )
    }
}
```

### Default Hotkey

デフォルト: `Ctrl + Shift + 4`

macOS 標準の `Cmd + Shift + 4` と競合しないよう、`Ctrl` を使用。
