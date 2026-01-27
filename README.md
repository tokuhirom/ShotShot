# ShotShot

macOS用のスクリーンショットツール。Skitch風のUXで、領域選択でキャプチャし、矢印・テキスト・モザイクの注釈を追加可能。

![alt text](image.png)

## 機能

- **メニューバー常駐**: アプリはメニューバーに常駐
- **グローバルホットキー**: デフォルト Ctrl+Shift+4 でキャプチャ開始
- **領域選択キャプチャ**: ScreenCaptureKit使用
- **Retina対応**: @2x でキャプチャ、ファイル名にも反映
- **注釈機能**:
  - 矢印（色・太さ変更可）
  - テキスト（フォント・サイズ・色変更可）
  - モザイク（ピクセル化）
- **画像保存**: PNG形式、デフォルト ~/Pictures/ShotShot/
- **クリップボードコピー**: 撮影後自動コピー

## 必要環境

- macOS 15.0+
- Xcode 16.0+
- Swift 6

## 開発

### ビルド

```bash
# デバッグビルド
./scripts/build.sh debug

# リリースビルド
./scripts/build.sh release
```

### 実行

```bash
# 最新のビルドを起動（なければ自動でビルド）
./scripts/run.sh
```

### Xcode で直接ビルド

```bash
xcodebuild -project shotshot.xcodeproj -scheme shotshot -configuration Debug build
```

### ビルド成果物の場所

ビルドされたアプリは以下に出力されます:

```
~/Library/Developer/Xcode/DerivedData/shotshot-*/Build/Products/Debug/ShotShot.app
```

## 使い方

1. アプリを起動すると、メニューバーにカメラアイコンが表示される
2. Ctrl+Shift+4 を押すか、メニューから「スクリーンショットを撮る」を選択
3. マウスでキャプチャしたい領域をドラッグして選択
4. エディタウィンドウが開き、注釈を追加可能
5. 「保存」で画像を保存、「クリップボードにコピー」でコピー

## 権限

このアプリは以下の権限を必要とします:

- **画面収録**: スクリーンショットを撮影するため

初回起動時にシステム設定での許可が必要です。

## ライセンス

MIT License
