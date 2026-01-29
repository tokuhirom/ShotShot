import AppKit
import SwiftUI

// IME対応のテキストビュー
struct IMEAwareTextField: NSViewRepresentable {
    @Binding var text: String
    var displayText: Binding<String>  // 表示用（縁取り用）
    var font: NSFont
    var textColor: NSColor
    var onCommit: () -> Void

    func makeNSView(context: Context) -> NSTextView {
        let textView = NSTextView()
        textView.isRichText = false
        textView.font = font
        textView.textColor = textColor
        textView.backgroundColor = .clear
        textView.drawsBackground = false
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = true
        textView.autoresizingMask = [.width, .height]
        textView.textContainer?.widthTracksTextView = false
        textView.textContainer?.heightTracksTextView = false
        textView.textContainer?.containerSize = NSSize(width: 10000, height: 10000)
        textView.isFieldEditor = false
        textView.delegate = context.coordinator
        return textView
    }

    func updateNSView(_ nsView: NSTextView, context: Context) {
        // 初期テキストの設定（初回のみ）
        if context.coordinator.isFirstUpdate && !text.isEmpty {
            nsView.string = text
            context.coordinator.isFirstUpdate = false
        }
        nsView.font = font
        nsView.textColor = textColor

        // 初回表示時にフォーカスを設定
        DispatchQueue.main.async {
            if nsView.window?.firstResponder != nsView {
                nsView.window?.makeFirstResponder(nsView)
            }
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, NSTextViewDelegate {
        var parent: IMEAwareTextField
        var isFirstUpdate = true

        init(_ parent: IMEAwareTextField) {
            self.parent = parent
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            // 表示用テキストは常に更新（縁取り表示用）
            parent.displayText.wrappedValue = textView.string
        }

        func textDidEndEditing(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            // 確定時のみ実際のテキストを更新
            parent.text = textView.string
            parent.displayText.wrappedValue = textView.string
            parent.onCommit()
        }
    }
}

enum ResizeHandle {
    case startPoint      // startPoint を動かす
    case endPoint        // endPoint を動かす
    case startXEndY      // startPoint.x と endPoint.y を動かす（四角形用）
    case endXStartY      // endPoint.x と startPoint.y を動かす（四角形用）
}

struct AnnotationCanvas: View {
    @Bindable var viewModel: EditorViewModel
    let canvasSize: CGSize
    let expandedSize: CGSize
    let imageOffset: CGPoint
    @State private var isEditing = false
    @State private var editingText = ""  // 確定済みテキスト
    @State private var displayText = ""  // 表示用テキスト（IME入力中も更新）
    @State private var editingPosition: CGPoint = .zero  // 表示座標
    @State private var editingImagePosition: CGPoint = .zero  // 画像座標（拡張計算用に固定保持）
    @State private var editingAnnotationId: UUID? = nil  // 編集中のテキスト注釈ID（nilなら新規作成）
    @State private var isDraggingAnnotation = false
    @State private var isResizingAnnotation = false
    @State private var activeResizeHandle: ResizeHandle? = nil
    @State private var dragStartPoint: CGPoint = .zero
    @State private var lastClickTime: Date = .distantPast
    @State private var lastClickPoint: CGPoint = .zero
    @State private var pendingSelectAnnotationId: UUID? = nil  // 描画ツールでのクリック選択用
    @FocusState private var isTextFieldFocused: Bool

    var body: some View {
        ZStack {
            Canvas { context, size in
                let scale = CGSize(
                    width: expandedSize.width / canvasSize.width,
                    height: expandedSize.height / canvasSize.height
                )

                for annotation in viewModel.annotations {
                    // モザイクはcompositeImageで適用済みなのでスキップ
                    if annotation.type != .mosaic {
                        drawAnnotation(annotation, context: &context, scale: scale)
                    }

                    // 選択中の注釈に枠を表示
                    if annotation.id == viewModel.selectedAnnotationId {
                        drawSelectionIndicator(for: annotation, context: &context, scale: scale)
                    }
                }

                if let current = viewModel.getCurrentAnnotation() {
                    drawAnnotation(current, context: &context, scale: scale)
                }

                // クロップオーバーレイを描画
                if let cropRect = viewModel.cropRect {
                    drawCropOverlay(cropRect: cropRect, context: &context, scale: scale, canvasSize: size)
                }
            }
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        handleDrag(value)
                    }
                    .onEnded { value in
                        handleDragEnd(value)
                    }
            )

            if isEditing {
                // 表示スケールを計算
                let displayScale = canvasSize.height / expandedSize.height
                let scaledFontSize = viewModel.fontSize * displayScale
                // 画像座標からの動的な表示位置（拡張に追従）
                let scale = CGSize(
                    width: expandedSize.width / canvasSize.width,
                    height: expandedSize.height / canvasSize.height
                )
                let dynamicEditingPos = CGPoint(
                    x: (editingImagePosition.x + viewModel.imageOffset.x) / scale.width,
                    y: (editingImagePosition.y + viewModel.imageOffset.y) / scale.height
                )

                VStack {
                    HStack {
                        ZStack(alignment: .leading) {
                            // 縁取り用テキスト（白）- displayTextを使用
                            let strokeWidth: CGFloat = scaledFontSize * 0.08
                            let offsets: [(CGFloat, CGFloat)] = [
                                (-strokeWidth, -strokeWidth), (0, -strokeWidth), (strokeWidth, -strokeWidth),
                                (-strokeWidth, 0), (strokeWidth, 0),
                                (-strokeWidth, strokeWidth), (0, strokeWidth), (strokeWidth, strokeWidth)
                            ]
                            ForEach(0..<offsets.count, id: \.self) { i in
                                Text(displayText.isEmpty ? " " : displayText)
                                    .font(.system(size: scaledFontSize, weight: .bold))
                                    .foregroundColor(.white)
                                    .offset(x: offsets[i].0, y: offsets[i].1)
                            }

                            // IME対応入力フィールド
                            IMEAwareTextField(
                                text: $editingText,
                                displayText: $displayText,
                                font: NSFont.boldSystemFont(ofSize: scaledFontSize),
                                textColor: viewModel.selectedColor,
                                onCommit: {
                                    finishTextEditing()
                                }
                            )
                            .frame(minWidth: 100, minHeight: scaledFontSize * 1.5)
                        }
                        .fixedSize()
                        .padding(.horizontal, 4)
                        .padding(.vertical, 2)
                        .background(
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color.black.opacity(0.3))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 4)
                                .stroke(Color.accentColor, lineWidth: 2)
                        )
                        Spacer()
                    }
                    .padding(.leading, dynamicEditingPos.x)
                    .padding(.top, dynamicEditingPos.y)
                    Spacer()
                }
            }
        }
        .onChange(of: viewModel.selectedTool) { _, _ in
            // ツール切替時にテキスト編集中ならIMEを確定
            if isEditing {
                if let window = NSApp.keyWindow {
                    window.makeFirstResponder(nil)
                }
            }
        }
        .onChange(of: displayText) { _, newText in
            updateEditingTextBounds(text: newText)
        }
        .onChange(of: isEditing) { _, editing in
            if !editing {
                viewModel.editingTextBounds = nil
            }
        }
    }

    private func handleDrag(_ value: DragGesture.Value) {
        // テキスト編集中に他の場所をクリックしたら編集を終了
        if isEditing {
            // IMEの未確定文字列を確定させるため、フォーカスを外す
            if let window = NSApp.keyWindow {
                window.makeFirstResponder(nil)
            }
            // finishTextEditingはcontrolTextDidEndEditingから呼ばれる
            return
        }

        let scale = CGSize(
            width: expandedSize.width / canvasSize.width,
            height: expandedSize.height / canvasSize.height
        )

        let scaledStart = CGPoint(
            x: value.startLocation.x * scale.width - imageOffset.x,
            y: value.startLocation.y * scale.height - imageOffset.y
        )
        let scaledCurrent = CGPoint(
            x: value.location.x * scale.width - imageOffset.x,
            y: value.location.y * scale.height - imageOffset.y
        )

        // ドラッグ開始時
        if viewModel.getCurrentAnnotation() == nil && !isDraggingAnnotation && !isResizingAnnotation {
            if viewModel.selectedTool == .select {
                // ダブルクリック検出
                let now = Date()
                let clickInterval = now.timeIntervalSince(lastClickTime)
                let clickDistance = hypot(value.startLocation.x - lastClickPoint.x, value.startLocation.y - lastClickPoint.y)
                let isDoubleClick = clickInterval < 0.3 && clickDistance < 10

                lastClickTime = now
                lastClickPoint = value.startLocation

                // 選択ツール: 選択・移動・リサイズ
                if let selectedId = viewModel.selectedAnnotationId,
                   let annotation = viewModel.annotations.first(where: { $0.id == selectedId }),
                   let handle = hitTestResizeHandle(annotation: annotation, point: value.startLocation, scale: scale) {
                    // リサイズハンドルをヒット → リサイズモード
                    viewModel.saveStateForUndo()
                    isResizingAnnotation = true
                    activeResizeHandle = handle
                    dragStartPoint = scaledStart
                } else if let hitAnnotation = viewModel.hitTest(at: scaledStart) {
                    // テキスト注釈をダブルクリック → 編集モード
                    if isDoubleClick && hitAnnotation.type == .text {
                        startEditingTextAnnotation(hitAnnotation)
                        return
                    }
                    // 既存の注釈をヒット → 選択・移動モード
                    viewModel.saveStateForUndo()
                    viewModel.selectAnnotation(id: hitAnnotation.id)
                    isDraggingAnnotation = true
                    dragStartPoint = scaledStart
                } else {
                    // ヒットなし → 選択解除
                    viewModel.deselectAnnotation()
                }
            } else if viewModel.selectedTool == .crop {
                // クロップツール: 切り抜き領域の選択開始
                if viewModel.cropRect == nil {
                    viewModel.startCrop(at: scaledStart)
                }
            } else if viewModel.selectedTool == .text {
                // テキストツール: 既存注釈のクリック選択 or 新規テキスト入力
                if let hitAnnotation = viewModel.hitTest(at: scaledStart) {
                    pendingSelectAnnotationId = hitAnnotation.id
                } else {
                    viewModel.deselectAnnotation()
                }
            } else {
                // 描画ツール: 既存注釈のクリック選択 or 新規作成
                if let hitAnnotation = viewModel.hitTest(at: scaledStart) {
                    // 既存注釈あり → クリックなら選択、ドラッグなら新規作成
                    pendingSelectAnnotationId = hitAnnotation.id
                } else {
                    viewModel.deselectAnnotation()
                    viewModel.startAnnotation(at: scaledStart)
                }
            }
        }

        // 描画ツールで既存注釈上からドラッグ開始した場合、一定距離以上で新規作成に切り替え
        if let _ = pendingSelectAnnotationId {
            let dragDistance = hypot(value.location.x - value.startLocation.x, value.location.y - value.startLocation.y)
            if dragDistance > 5 {
                pendingSelectAnnotationId = nil
                viewModel.deselectAnnotation()
                // テキストツールの場合は新規注釈作成しない（handleDragEndでテキスト入力開始）
                if viewModel.selectedTool != .text {
                    viewModel.startAnnotation(at: scaledStart)
                }
            }
        }

        // ドラッグ中
        if isResizingAnnotation, let handle = activeResizeHandle {
            viewModel.resizeSelectedAnnotation(handle: handle, to: scaledCurrent)
        } else if isDraggingAnnotation {
            let delta = CGPoint(
                x: scaledCurrent.x - dragStartPoint.x,
                y: scaledCurrent.y - dragStartPoint.y
            )
            viewModel.moveSelectedAnnotation(by: delta)
            dragStartPoint = scaledCurrent
        } else if viewModel.selectedTool == .crop {
            // クロップ領域を更新
            viewModel.updateCrop(to: scaledCurrent)
        } else if viewModel.selectedTool != .text && viewModel.selectedTool != .select {
            viewModel.updateAnnotation(to: scaledCurrent)
        }
    }

    private func handleDragEnd(_ value: DragGesture.Value) {
        let scale = CGSize(
            width: expandedSize.width / canvasSize.width,
            height: expandedSize.height / canvasSize.height
        )

        let scaledEnd = CGPoint(
            x: value.location.x * scale.width - imageOffset.x,
            y: value.location.y * scale.height - imageOffset.y
        )

        if let annotationId = pendingSelectAnnotationId {
            // クリックで既存注釈を選択
            pendingSelectAnnotationId = nil
            viewModel.selectAnnotation(id: annotationId)
            viewModel.selectedTool = .select
        } else if isResizingAnnotation {
            // リサイズ完了
            isResizingAnnotation = false
            activeResizeHandle = nil
        } else if isDraggingAnnotation {
            // 移動完了
            isDraggingAnnotation = false
        } else if viewModel.selectedTool == .text {
            editingPosition = value.location
            // 画像座標を固定保持（拡張によるoffset変動の影響を受けない）
            editingImagePosition = scaledEnd
            isEditing = true
            // 初期バウンズを設定（空テキスト）
            updateEditingTextBounds(text: "")
        } else {
            viewModel.finishAnnotation(at: scaledEnd)
        }
    }

    private func hitTestResizeHandle(annotation: Annotation, point: CGPoint, scale: CGSize) -> ResizeHandle? {
        let displayStart = CGPoint(
            x: (annotation.startPoint.x + imageOffset.x) / scale.width,
            y: (annotation.startPoint.y + imageOffset.y) / scale.height
        )
        let displayEnd = CGPoint(
            x: (annotation.endPoint.x + imageOffset.x) / scale.width,
            y: (annotation.endPoint.y + imageOffset.y) / scale.height
        )

        let handleSize: CGFloat = 16  // ヒット判定用に大きめ

        // 矢印の場合は startPoint と endPoint の2点のみ
        if annotation.type == .arrow {
            let handles: [(ResizeHandle, CGPoint)] = [
                (.startPoint, displayStart),
                (.endPoint, displayEnd)
            ]
            for (handle, handlePoint) in handles {
                let handleRect = CGRect(
                    x: handlePoint.x - handleSize / 2,
                    y: handlePoint.y - handleSize / 2,
                    width: handleSize,
                    height: handleSize
                )
                if handleRect.contains(point) {
                    return handle
                }
            }
        } else {
            // 四角形/モザイク/テキストの場合は四隅
            let handles: [(ResizeHandle, CGPoint)] = [
                (.startPoint, displayStart),
                (.endPoint, displayEnd),
                (.startXEndY, CGPoint(x: displayStart.x, y: displayEnd.y)),
                (.endXStartY, CGPoint(x: displayEnd.x, y: displayStart.y))
            ]
            for (handle, handlePoint) in handles {
                let handleRect = CGRect(
                    x: handlePoint.x - handleSize / 2,
                    y: handlePoint.y - handleSize / 2,
                    width: handleSize,
                    height: handleSize
                )
                if handleRect.contains(point) {
                    return handle
                }
            }
        }
        return nil
    }

    private func getSelectionRect(annotation: Annotation, displayStart: CGPoint, displayEnd: CGPoint) -> CGRect {
        switch annotation.type {
        case .arrow:
            return CGRect(
                x: min(displayStart.x, displayEnd.x) - 8,
                y: min(displayStart.y, displayEnd.y) - 8,
                width: abs(displayEnd.x - displayStart.x) + 16,
                height: abs(displayEnd.y - displayStart.y) + 16
            )
        case .rectangle, .mosaic:
            return CGRect(
                x: min(displayStart.x, displayEnd.x) - 4,
                y: min(displayStart.y, displayEnd.y) - 4,
                width: abs(displayEnd.x - displayStart.x) + 8,
                height: abs(displayEnd.y - displayStart.y) + 8
            )
        case .text:
            let fontSize = annotation.fontSize ?? 16.0
            let textWidth = CGFloat((annotation.text ?? "").count) * fontSize * 0.6
            return CGRect(
                x: displayEnd.x - 4,
                y: displayEnd.y - 4,
                width: max(textWidth, 20) + 8,
                height: fontSize * 1.2 + 8
            )
        }
    }

    private func updateEditingTextBounds(text: String) {
        guard isEditing else { return }
        // editingImagePosition は編集開始時に固定された画像座標を使う
        // （拡張によるimageOffset変動の影響を受けない）
        viewModel.editingTextBounds = Annotation.computeTextBounds(
            text: text,
            fontSize: viewModel.fontSize,
            origin: editingImagePosition
        )
    }

    private func finishTextEditing() {
        // displayTextを使用（最新の入力内容）
        let finalText = displayText

        defer {
            isEditing = false
            editingText = ""
            displayText = ""
            editingAnnotationId = nil
        }

        guard !finalText.isEmpty else {
            // 空の場合、編集中だった既存注釈は削除
            if let annotationId = editingAnnotationId {
                viewModel.deleteAnnotation(id: annotationId)
            }
            return
        }

        if let annotationId = editingAnnotationId {
            // 既存の注釈を更新
            viewModel.updateTextAnnotation(id: annotationId, text: finalText)
        } else {
            // 新規作成（editingImagePosition は編集開始時に固定された画像座標）
            viewModel.addTextAnnotation(at: editingImagePosition, text: finalText)
        }
    }

    private func startEditingTextAnnotation(_ annotation: Annotation) {
        guard annotation.type == .text, let text = annotation.text else { return }

        let scale = CGSize(
            width: expandedSize.width / canvasSize.width,
            height: expandedSize.height / canvasSize.height
        )

        // 画像座標系からキャンバス座標系に変換（imageOffset を加算）
        editingPosition = CGPoint(
            x: (annotation.endPoint.x + imageOffset.x) / scale.width,
            y: (annotation.endPoint.y + imageOffset.y) / scale.height
        )
        // 画像座標を固定保持
        editingImagePosition = annotation.endPoint
        editingText = text
        displayText = text
        editingAnnotationId = annotation.id
        isEditing = true
        // 編集中テキストのバウンズを設定
        updateEditingTextBounds(text: text)

        // 編集中は選択解除
        viewModel.deselectAnnotation()
    }

    private func drawAnnotation(_ annotation: Annotation, context: inout GraphicsContext, scale: CGSize) {
        let displayStart = CGPoint(
            x: (annotation.startPoint.x + imageOffset.x) / scale.width,
            y: (annotation.startPoint.y + imageOffset.y) / scale.height
        )
        let displayEnd = CGPoint(
            x: (annotation.endPoint.x + imageOffset.x) / scale.width,
            y: (annotation.endPoint.y + imageOffset.y) / scale.height
        )

        switch annotation.type {
        case .arrow:
            drawArrow(from: displayStart, to: displayEnd, color: annotation.color, lineWidth: annotation.lineWidth, context: &context)
        case .rectangle:
            drawRectangle(from: displayStart, to: displayEnd, color: annotation.color, lineWidth: annotation.lineWidth, cornerRadius: annotation.cornerRadius, context: &context)
        case .text:
            if let text = annotation.text {
                // フォントサイズも表示スケールに合わせる
                let scaledFontSize = (annotation.fontSize ?? 16) / scale.height
                drawText(text, at: displayEnd, color: annotation.color, fontSize: scaledFontSize, context: &context)
            }
        case .mosaic:
            drawMosaicPreview(from: displayStart, to: displayEnd, context: &context)
        }
    }

    private func drawArrow(from start: CGPoint, to end: CGPoint, color: NSColor, lineWidth: CGFloat, context: inout GraphicsContext) {
        let angle = atan2(end.y - start.y, end.x - start.x)
        let length = hypot(end.x - start.x, end.y - start.y)

        guard length > 5 else { return }

        // Arrow dimensions
        let baseWidth = lineWidth * 0.15
        let headWidth = lineWidth * 3
        let headLength = lineWidth * 6

        // Calculate perpendicular direction
        let perpAngle = angle + .pi / 2

        // Shaft tapers from baseWidth at start to headWidth at head base
        let shaftLength = max(0, length - headLength)

        // Points for the tapered shaft
        let startLeft = CGPoint(
            x: start.x + baseWidth * cos(perpAngle),
            y: start.y + baseWidth * sin(perpAngle)
        )
        let startRight = CGPoint(
            x: start.x - baseWidth * cos(perpAngle),
            y: start.y - baseWidth * sin(perpAngle)
        )

        // Point where shaft meets head
        let shaftEnd = CGPoint(
            x: start.x + shaftLength * cos(angle),
            y: start.y + shaftLength * sin(angle)
        )
        let shaftEndLeft = CGPoint(
            x: shaftEnd.x + headWidth * 0.5 * cos(perpAngle),
            y: shaftEnd.y + headWidth * 0.5 * sin(perpAngle)
        )
        let shaftEndRight = CGPoint(
            x: shaftEnd.x - headWidth * 0.5 * cos(perpAngle),
            y: shaftEnd.y - headWidth * 0.5 * sin(perpAngle)
        )

        // Arrow head points
        let headLeft = CGPoint(
            x: shaftEnd.x + headWidth * cos(perpAngle),
            y: shaftEnd.y + headWidth * sin(perpAngle)
        )
        let headRight = CGPoint(
            x: shaftEnd.x - headWidth * cos(perpAngle),
            y: shaftEnd.y - headWidth * sin(perpAngle)
        )

        // Build arrow path
        var arrowPath = Path()
        arrowPath.move(to: startLeft)
        arrowPath.addLine(to: shaftEndLeft)
        arrowPath.addLine(to: headLeft)
        arrowPath.addLine(to: end)
        arrowPath.addLine(to: headRight)
        arrowPath.addLine(to: shaftEndRight)
        arrowPath.addLine(to: startRight)
        arrowPath.closeSubpath()

        // Draw outline
        context.stroke(arrowPath, with: .color(.white), lineWidth: lineWidth * 0.8)

        // Fill arrow
        context.fill(arrowPath, with: .color(Color(nsColor: color)))
    }

    private func drawText(_ text: String, at point: CGPoint, color: NSColor, fontSize: CGFloat, context: inout GraphicsContext) {
        // 白い縁取り
        let strokeWidth: CGFloat = fontSize * 0.08
        let offsets: [(CGFloat, CGFloat)] = [
            (-strokeWidth, -strokeWidth), (0, -strokeWidth), (strokeWidth, -strokeWidth),
            (-strokeWidth, 0), (strokeWidth, 0),
            (-strokeWidth, strokeWidth), (0, strokeWidth), (strokeWidth, strokeWidth)
        ]

        for offset in offsets {
            let outlineText = Text(text)
                .font(.system(size: fontSize, weight: .bold))
                .foregroundColor(.white)
            context.draw(outlineText, at: CGPoint(x: point.x + offset.0, y: point.y + offset.1), anchor: .topLeading)
        }

        // メインテキスト
        let mainText = Text(text)
            .font(.system(size: fontSize, weight: .bold))
            .foregroundColor(Color(nsColor: color))
        context.draw(mainText, at: point, anchor: .topLeading)
    }

    private func drawRectangle(from start: CGPoint, to end: CGPoint, color: NSColor, lineWidth: CGFloat, cornerRadius: CGFloat?, context: inout GraphicsContext) {
        let rect = CGRect(
            x: min(start.x, end.x),
            y: min(start.y, end.y),
            width: abs(end.x - start.x),
            height: abs(end.y - start.y)
        )

        guard rect.width > 2 && rect.height > 2 else { return }

        let path: Path
        if let radius = cornerRadius, radius > 0 {
            path = Path(roundedRect: rect, cornerRadius: radius)
        } else {
            path = Path(rect)
        }

        // Draw white outline
        context.stroke(path, with: .color(.white), lineWidth: lineWidth + 4)

        // Draw colored rectangle
        context.stroke(path, with: .color(Color(nsColor: color)), lineWidth: lineWidth)
    }

    private func drawMosaicPreview(from start: CGPoint, to end: CGPoint, context: inout GraphicsContext) {
        let rect = CGRect(
            x: min(start.x, end.x),
            y: min(start.y, end.y),
            width: abs(end.x - start.x),
            height: abs(end.y - start.y)
        )

        let path = Path(rect)
        context.stroke(path, with: .color(.gray), style: StrokeStyle(lineWidth: 2, dash: [5, 5]))
    }

    private func drawSelectionIndicator(for annotation: Annotation, context: inout GraphicsContext, scale: CGSize) {
        let displayStart = CGPoint(
            x: (annotation.startPoint.x + imageOffset.x) / scale.width,
            y: (annotation.startPoint.y + imageOffset.y) / scale.height
        )
        let displayEnd = CGPoint(
            x: (annotation.endPoint.x + imageOffset.x) / scale.width,
            y: (annotation.endPoint.y + imageOffset.y) / scale.height
        )

        let selectionRect: CGRect
        switch annotation.type {
        case .arrow:
            // 矢印の場合は始点と終点を含む矩形
            selectionRect = CGRect(
                x: min(displayStart.x, displayEnd.x) - 8,
                y: min(displayStart.y, displayEnd.y) - 8,
                width: abs(displayEnd.x - displayStart.x) + 16,
                height: abs(displayEnd.y - displayStart.y) + 16
            )
        case .rectangle, .mosaic:
            selectionRect = CGRect(
                x: min(displayStart.x, displayEnd.x) - 4,
                y: min(displayStart.y, displayEnd.y) - 4,
                width: abs(displayEnd.x - displayStart.x) + 8,
                height: abs(displayEnd.y - displayStart.y) + 8
            )
        case .text:
            // テキストも表示スケールに合わせて描画されるので、boundsもスケールする
            if let bounds = annotation.textBounds() {
                selectionRect = CGRect(
                    x: displayEnd.x - 4,
                    y: displayEnd.y - 4,
                    width: bounds.width / scale.width + 8,
                    height: bounds.height / scale.height + 8
                )
            } else {
                selectionRect = CGRect(x: displayEnd.x - 4, y: displayEnd.y - 4, width: 28, height: 28)
            }
        }

        let path = Path(selectionRect)
        context.stroke(path, with: .color(.blue), style: StrokeStyle(lineWidth: 2, dash: [5, 3]))

        // ハンドルを描画
        let handleSize: CGFloat = 8
        let handles: [CGPoint]

        if annotation.type == .arrow {
            // 矢印の場合は startPoint と endPoint の2点のみ
            handles = [displayStart, displayEnd]
        } else {
            // 四角形/モザイク/テキストの場合は四隅
            handles = [
                displayStart,
                displayEnd,
                CGPoint(x: displayStart.x, y: displayEnd.y),
                CGPoint(x: displayEnd.x, y: displayStart.y)
            ]
        }

        for handle in handles {
            let handleRect = CGRect(
                x: handle.x - handleSize / 2,
                y: handle.y - handleSize / 2,
                width: handleSize,
                height: handleSize
            )
            context.fill(Path(handleRect), with: .color(.white))
            context.stroke(Path(handleRect), with: .color(.blue), lineWidth: 1)
        }
    }

    private func drawCropOverlay(cropRect: CGRect, context: inout GraphicsContext, scale: CGSize, canvasSize: CGSize) {
        // 画像座標系からキャンバス座標系に変換（imageOffset を加算）
        let displayRect = CGRect(
            x: (cropRect.origin.x + imageOffset.x) / scale.width,
            y: (cropRect.origin.y + imageOffset.y) / scale.height,
            width: cropRect.width / scale.width,
            height: cropRect.height / scale.height
        )

        // 外側を暗くするオーバーレイ
        let dimColor = Color.black.opacity(0.5)

        // 上部
        if displayRect.minY > 0 {
            let topRect = CGRect(x: 0, y: 0, width: canvasSize.width, height: displayRect.minY)
            context.fill(Path(topRect), with: .color(dimColor))
        }

        // 下部
        if displayRect.maxY < canvasSize.height {
            let bottomRect = CGRect(x: 0, y: displayRect.maxY, width: canvasSize.width, height: canvasSize.height - displayRect.maxY)
            context.fill(Path(bottomRect), with: .color(dimColor))
        }

        // 左部
        if displayRect.minX > 0 {
            let leftRect = CGRect(x: 0, y: displayRect.minY, width: displayRect.minX, height: displayRect.height)
            context.fill(Path(leftRect), with: .color(dimColor))
        }

        // 右部
        if displayRect.maxX < canvasSize.width {
            let rightRect = CGRect(x: displayRect.maxX, y: displayRect.minY, width: canvasSize.width - displayRect.maxX, height: displayRect.height)
            context.fill(Path(rightRect), with: .color(dimColor))
        }

        // クロップ領域の枠線
        let borderPath = Path(displayRect)
        context.stroke(borderPath, with: .color(.white), lineWidth: 2)

        // 四隅のハンドル
        let handleSize: CGFloat = 10
        let corners = [
            CGPoint(x: displayRect.minX, y: displayRect.minY),
            CGPoint(x: displayRect.maxX, y: displayRect.minY),
            CGPoint(x: displayRect.minX, y: displayRect.maxY),
            CGPoint(x: displayRect.maxX, y: displayRect.maxY)
        ]

        for corner in corners {
            let handleRect = CGRect(
                x: corner.x - handleSize / 2,
                y: corner.y - handleSize / 2,
                width: handleSize,
                height: handleSize
            )
            context.fill(Path(handleRect), with: .color(.white))
            context.stroke(Path(handleRect), with: .color(.accentColor), lineWidth: 2)
        }
    }
}
