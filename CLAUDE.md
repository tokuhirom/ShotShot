# ShotShot - Claude Code 用プロジェクト情報

## ビルド & 実行

```bash
# デバッグビルド
./scripts/build.sh debug

# リリースビルド
./scripts/build.sh release

# 実行（ビルドがなければ自動ビルド、ログ出力付き）
./scripts/run.sh
```

## デバッグ

### クラッシュログの取得

macOSのクラッシュログは以下に保存される：
```bash
~/Library/Logs/DiagnosticReports/
```

最新のShotShotクラッシュログを表示：
```bash
cat ~/Library/Logs/DiagnosticReports/$(ls -t ~/Library/Logs/DiagnosticReports/ | grep -i shotshot | head -1)
```

`./scripts/run.sh` で実行した場合、クラッシュ時に自動でログが表示される。

### アプリログ

`./scripts/run.sh` で実行すると `./logs/` にログファイルが保存される。

macOS GUIアプリでは `print()` が出力されない場合があるので、重要なログは `NSLog()` を使用する。

## 技術スタック

- Swift 6 (strict concurrency)
- SwiftUI + AppKit
- ScreenCaptureKit（画面キャプチャ）
- macOS 26.0+

## アーキテクチャ

```
shotshot/
├── App/           # エントリポイント、AppDelegate
├── Features/
│   ├── Capture/   # 画面キャプチャ、領域選択UI
│   ├── Editor/    # 編集ウィンドウ
│   ├── Annotations/ # 矢印、四角、テキスト、モザイク
│   ├── MenuBar/   # メニューバー常駐
│   └── Settings/  # 設定画面
├── Models/        # データモデル
├── Services/      # クリップボード、画像保存、ホットキー
└── Resources/     # アセット、Info.plist
```

## 注意点

- `@MainActor` を多用している。Swift 6 の並行処理制限に注意。
- NSWindowは `isReleasedWhenClosed = false` にしてARC管理にしている。
- NotificationCenterのクロージャベースのオブザーバーは戻り値のトークンを保存して削除すること。
