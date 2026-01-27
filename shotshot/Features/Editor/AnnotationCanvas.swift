import AppKit
import SwiftUI

enum ResizeHandle {
    case startPoint      // startPoint を動かす
    case endPoint        // endPoint を動かす
    case startXEndY      // startPoint.x と endPoint.y を動かす（四角形用）
    case endXStartY      // endPoint.x と startPoint.y を動かす（四角形用）
}

struct AnnotationCanvas: View {
    @Bindable var viewModel: EditorViewModel
    let canvasSize: CGSize
    let imageSize: NSSize
    @State private var isEditing = false
    @State private var editingText = ""
    @State private var editingPosition: CGPoint = .zero
    @State private var isDraggingAnnotation = false
    @State private var isResizingAnnotation = false
    @State private var activeResizeHandle: ResizeHandle? = nil
    @State private var dragStartPoint: CGPoint = .zero
    @FocusState private var isTextFieldFocused: Bool

    var body: some View {
        ZStack {
            Canvas { context, size in
                let scale = CGSize(
                    width: imageSize.width / canvasSize.width,
                    height: imageSize.height / canvasSize.height
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

            if isEditing && viewModel.selectedTool == .text {
                VStack {
                    HStack {
                        ZStack(alignment: .leading) {
                            // 縁取り用テキスト（白）
                            let strokeWidth: CGFloat = viewModel.fontSize * 0.08
                            let offsets: [(CGFloat, CGFloat)] = [
                                (-strokeWidth, -strokeWidth), (0, -strokeWidth), (strokeWidth, -strokeWidth),
                                (-strokeWidth, 0), (strokeWidth, 0),
                                (-strokeWidth, strokeWidth), (0, strokeWidth), (strokeWidth, strokeWidth)
                            ]
                            ForEach(0..<offsets.count, id: \.self) { i in
                                Text(editingText.isEmpty ? " " : editingText)
                                    .font(.system(size: viewModel.fontSize, weight: .bold))
                                    .foregroundColor(.white)
                                    .offset(x: offsets[i].0, y: offsets[i].1)
                            }

                            // 入力フィールド
                            TextField("", text: $editingText, onCommit: {
                                finishTextEditing()
                            })
                            .textFieldStyle(.plain)
                            .font(.system(size: viewModel.fontSize, weight: .bold))
                            .foregroundColor(Color(nsColor: viewModel.selectedColor))
                            .focused($isTextFieldFocused)
                        }
                        .fixedSize()
                        Spacer()
                    }
                    .padding(.leading, editingPosition.x)
                    .padding(.top, editingPosition.y)
                    Spacer()
                }
                .onAppear {
                    isTextFieldFocused = true
                }
            }
        }
    }

    private func handleDrag(_ value: DragGesture.Value) {
        // テキスト編集中に他の場所をクリックしたら編集を終了
        if isEditing {
            finishTextEditing()
            return
        }

        let scale = CGSize(
            width: imageSize.width / canvasSize.width,
            height: imageSize.height / canvasSize.height
        )

        let scaledStart = CGPoint(
            x: value.startLocation.x * scale.width,
            y: value.startLocation.y * scale.height
        )
        let scaledCurrent = CGPoint(
            x: value.location.x * scale.width,
            y: value.location.y * scale.height
        )

        // ドラッグ開始時
        if viewModel.getCurrentAnnotation() == nil && !isDraggingAnnotation && !isResizingAnnotation {
            if viewModel.selectedTool == .select {
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
                    // 既存の注釈をヒット → 選択・移動モード
                    viewModel.saveStateForUndo()
                    viewModel.selectAnnotation(id: hitAnnotation.id)
                    isDraggingAnnotation = true
                    dragStartPoint = scaledStart
                } else {
                    // ヒットなし → 選択解除
                    viewModel.deselectAnnotation()
                }
            } else if viewModel.selectedTool == .text {
                // テキストツール: クリック位置でテキスト入力開始（handleDragEndで処理）
                viewModel.deselectAnnotation()
            } else {
                // 描画ツール: 新規注釈作成
                viewModel.deselectAnnotation()
                viewModel.startAnnotation(at: scaledStart)
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
        } else if viewModel.selectedTool != .text && viewModel.selectedTool != .select {
            viewModel.updateAnnotation(to: scaledCurrent)
        }
    }

    private func handleDragEnd(_ value: DragGesture.Value) {
        let scale = CGSize(
            width: imageSize.width / canvasSize.width,
            height: imageSize.height / canvasSize.height
        )

        let scaledEnd = CGPoint(
            x: value.location.x * scale.width,
            y: value.location.y * scale.height
        )

        if isResizingAnnotation {
            // リサイズ完了
            isResizingAnnotation = false
            activeResizeHandle = nil
        } else if isDraggingAnnotation {
            // 移動完了
            isDraggingAnnotation = false
        } else if viewModel.selectedTool == .text {
            editingPosition = value.location
            isEditing = true
        } else {
            viewModel.finishAnnotation(at: scaledEnd)
        }
    }

    private func hitTestResizeHandle(annotation: Annotation, point: CGPoint, scale: CGSize) -> ResizeHandle? {
        let displayStart = CGPoint(
            x: annotation.startPoint.x / scale.width,
            y: annotation.startPoint.y / scale.height
        )
        let displayEnd = CGPoint(
            x: annotation.endPoint.x / scale.width,
            y: annotation.endPoint.y / scale.height
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

    private func finishTextEditing() {
        guard !editingText.isEmpty else {
            isEditing = false
            editingText = ""
            return
        }

        let scale = CGSize(
            width: imageSize.width / canvasSize.width,
            height: imageSize.height / canvasSize.height
        )

        let scaledPosition = CGPoint(
            x: editingPosition.x * scale.width,
            y: editingPosition.y * scale.height
        )

        viewModel.addTextAnnotation(at: scaledPosition, text: editingText)
        isEditing = false
        editingText = ""
    }

    private func drawAnnotation(_ annotation: Annotation, context: inout GraphicsContext, scale: CGSize) {
        let displayStart = CGPoint(
            x: annotation.startPoint.x / scale.width,
            y: annotation.startPoint.y / scale.height
        )
        let displayEnd = CGPoint(
            x: annotation.endPoint.x / scale.width,
            y: annotation.endPoint.y / scale.height
        )

        switch annotation.type {
        case .arrow:
            drawArrow(from: displayStart, to: displayEnd, color: annotation.color, lineWidth: annotation.lineWidth, context: &context)
        case .rectangle:
            drawRectangle(from: displayStart, to: displayEnd, color: annotation.color, lineWidth: annotation.lineWidth, cornerRadius: annotation.cornerRadius, context: &context)
        case .text:
            if let text = annotation.text {
                drawText(text, at: displayEnd, color: annotation.color, fontSize: annotation.fontSize ?? 16, context: &context)
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
            x: annotation.startPoint.x / scale.width,
            y: annotation.startPoint.y / scale.height
        )
        let displayEnd = CGPoint(
            x: annotation.endPoint.x / scale.width,
            y: annotation.endPoint.y / scale.height
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
            let fontSize = annotation.fontSize ?? 16.0
            let textWidth = CGFloat((annotation.text ?? "").count) * fontSize * 0.6
            selectionRect = CGRect(
                x: displayEnd.x - 4,
                y: displayEnd.y - 4,
                width: max(textWidth, 20) + 8,
                height: fontSize * 1.2 + 8
            )
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
}
