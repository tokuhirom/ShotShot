# ADR 0001: MVVM + Feature-based アーキテクチャの採用

## Status

Accepted

## Context

macOS スクリーンショットツールを開発するにあたり、コードベースの構成方針を決定する必要があった。

選択肢:
1. MVC (Model-View-Controller) - AppKit の伝統的なパターン
2. MVVM (Model-View-ViewModel) - SwiftUI との親和性が高い
3. TCA (The Composable Architecture) - 状態管理が厳格だが学習コストが高い

## Decision

MVVM + Feature-based 構成を採用する。

```
shotshot/
├── App/           # アプリケーションエントリポイント
├── Features/      # 機能ごとのモジュール
│   ├── Capture/
│   ├── Editor/
│   ├── Annotations/
│   ├── MenuBar/
│   └── Settings/
├── Models/        # 共有データモデル
├── Services/      # システム API の抽象化
└── Resources/
```

## Consequences

### Positive
- SwiftUI の `@Observable` と自然に統合できる
- 機能ごとにコードが分離され、理解しやすい
- テスト時に ViewModel を単独でテスト可能

### Negative
- 小規模アプリには若干オーバーエンジニアリング
- Feature 間の依存関係管理が必要
