# スクロールキャプチャ 画像スティッチングアルゴリズム

## 概要

ShotShotのスクロールキャプチャ機能で使用している画像結合アルゴリズムの説明。

## 全体フロー

```
1. ユーザーがスクロールしている間、複数の画像をキャプチャ
2. 連続する画像ペア (image[i], image[i+1]) ごとに:
   a. 重複画像かチェック（全体の類似度 > 85%）
   b. 重複でなければ、オーバーラップ領域を検出
3. オーバーラップ領域を除去しながら画像を結合
```

## 画像の座標系

```
CGImage / ピクセルバッファ:
┌─────────────────────┐  ← Row 0 (画像の上端)
│                     │
│                     │
│                     │
│                     │
└─────────────────────┘  ← Row (height-1) (画像の下端)
```

CGImageをCGContextに変換なしで描画した場合：
- CGContextの原点は左下
- CGImageの原点は左上
- 結果：バッファのRow 0 = 画像の視覚的な上端

## オーバーラップ検出アルゴリズム

### 目的
以下の間でオーバーラップするピクセル数を検出：
- `topImage`（上の画像）の**下部**
- `bottomImage`（下の画像）の**上部**

```
topImage（上の画像）:
┌─────────────────────┐
│                     │
│                     │
│   （関係ない部分）    │
│                     │
├─────────────────────┤ ← topHeight - overlap
│  オーバーラップ領域   │   （下部）
└─────────────────────┘ ← topHeight - 1

bottomImage（下の画像）:
┌─────────────────────┐ ← Row 0
│  オーバーラップ領域   │   （上部）
├─────────────────────┤ ← overlap - 1
│                     │
│   （関係ない部分）    │
│                     │
│                     │
└─────────────────────┘
```

### パラメータ

| パラメータ | 値 | 説明 |
|-----------|-------|-------------|
| `maxSearchRange` | height * 90% | 探索する最大オーバーラップ（画像高さの90%まで） |
| `minOverlap` | 10 | 考慮する最小オーバーラップ |
| `matchThreshold` | 0.65 (65%) | オーバーラップを認める類似度閾値 |
| `colorTolerance` | 25 | 「一致」とみなすピクセルの色差許容値 |

**重要**: `maxSearchRange`を大きくしないと、ゆっくりスクロールした場合（大きなオーバーラップ）を検出できない。

### アルゴリズム手順

#### ステップ1: 重複検出
```
1. 画像全体からピクセルをサンプリング（8行ごと、8列ごと）
2. image1とimage2の対応するピクセルを比較
3. 類似度 > 85% なら重複とみなす → overlap = 画像の高さ全体
```

#### ステップ2: 粗い探索
```
for overlap in [maxSearchRange, maxSearchRange-5, ..., minOverlap]:
    similarity = compareBands(topImage, bottomImage, overlap)
    if similarity > bestSimilarity:
        bestSimilarity = similarity
        if similarity > matchThreshold:
            bestOverlap = overlap
```

#### ステップ3: 精密化
```
for offset in [-4, -3, ..., 3, 4]:
    overlap = bestOverlap + offset
    similarity = compareBands(topImage, bottomImage, overlap)
    if similarity > bestSimilarity:
        bestSimilarity = similarity
        bestOverlap = overlap
```

### ピクセル比較 (calculateRowSimilarity)

```swift
// topImageの下部とbottomImageの上部を比較
topStartRow = topHeight - overlap    // topImageでのオーバーラップ開始行
bottomStartRow = 0                   // bottomImageでのオーバーラップ開始行

// 4列ごと、2行ごとにサンプリング
for rowOffset in stride(0, overlap, step=2):
    for col in stride(0, width, step=4):
        topPixel = topImage[topStartRow + rowOffset][col]
        bottomPixel = bottomImage[bottomStartRow + rowOffset][col]

        // BGRAフォーマット (premultipliedFirst + byteOrder32Little)
        bDiff = abs(topPixel.B - bottomPixel.B)
        gDiff = abs(topPixel.G - bottomPixel.G)
        rDiff = abs(topPixel.R - bottomPixel.R)

        if bDiff <= 25 && gDiff <= 25 && rDiff <= 25:
            matchingPixels++
        totalSampled++

similarity = matchingPixels / totalSampled
```

## 画像の結合

### 合計高さの計算
```
totalHeight = 全画像の高さの合計 - 全オーバーラップの合計
```

### 描画順序
CGContextは左下が原点なので、**下から上へ**画像を描画。
各画像（最後以外）は、下部のオーバーラップ部分をクロップしてから描画する：

```swift
var currentY = 0

// 画像を逆順で処理（最後の画像から）
for i in reversed(0..<images.count):
    image = images[i]

    if i == lastIndex:
        // 最後の画像：そのまま描画
        context.draw(image, in: CGRect(0, currentY, width, image.height))
        currentY += image.height
    else:
        // その他の画像：下部のオーバーラップをクロップ
        cropHeight = image.height - overlaps[i]
        // CGImageは左上原点なので、y=0から上部をクロップ
        cropRect = CGRect(0, 0, image.width, cropHeight)
        croppedImage = image.cropping(to: cropRect)

        context.draw(croppedImage, in: CGRect(0, currentY, width, cropHeight))
        currentY += cropHeight
```

## キャプチャ時の注意点

- **オーバーレイウィンドウの除外**: スクロール中に表示されるShotShotのUI（Doneボタンなど）はキャプチャから自動的に除外される
- `SCContentFilter(display:excludingWindows:)` でオーバーレイウィンドウを除外

## 既知の問題

1. **低い類似度**: 視覚的にオーバーラップがあっても、類似度が65-78%程度
2. **動的コンテンツ**: 動画やアニメーションが誤検出の原因になる
3. **高速スクロール**: オーバーラップのない画像がキャプチャされる可能性

## デバッグモード

`SHOTSHOT_SCROLL_DEBUG=1` で中間画像を保存：
```bash
SHOTSHOT_SCROLL_DEBUG=1 ./scripts/run.sh
```

保存先: `$TMPDIR/ShotShot_Debug/scroll_<timestamp>/capture_XXX.png`

## デバッグツール

保存されたデバッグ画像を分析するCLIツール：

```bash
# 分析のみ（各画像のどの部分を使うか表示）
swift tools/stitch_debug.swift /path/to/ShotShot_Debug/scroll_XXXX

# 分析 + 結果画像を出力
swift tools/stitch_debug.swift /path/to/ShotShot_Debug/scroll_XXXX output.png
```

出力例：
```
Image | Height | Use Y range  | Overlap | Similarity
------|--------|--------------|---------|----------
    1 |   1172 |    0 -  123 |    1049 |  99.3%
    2 |   1172 |    0 -  565 |     607 |  98.5%
    ...
```
