import AppKit
import SwiftUI

// IME-aware text view
struct IMEAwareTextField: NSViewRepresentable {
    @Binding var text: String
    var displayText: Binding<String>  // Display text (for outline)
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
        // Set initial text (first time only)
        if context.coordinator.isFirstUpdate && !text.isEmpty {
            nsView.string = text
            context.coordinator.isFirstUpdate = false
        }
        nsView.font = font
        nsView.textColor = textColor

        // Set focus on first display
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
            // Always update display text (for outline rendering)
            parent.displayText.wrappedValue = textView.string
        }

        func textDidEndEditing(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            // Update actual text only on commit
            parent.text = textView.string
            parent.displayText.wrappedValue = textView.string
            parent.onCommit()
        }
    }
}

enum ResizeHandle {
    case startPoint      // Move startPoint
    case endPoint        // Move endPoint
    case startXEndY      // Move startPoint.x and endPoint.y (rectangle)
    case endXStartY      // Move endPoint.x and startPoint.y (rectangle)
}

struct AnnotationCanvas: View {
    @Bindable var viewModel: EditorViewModel
    let canvasSize: CGSize
    let expandedSize: CGSize
    let imageOffset: CGPoint
    @State private var isEditing = false
    @State private var editingText = ""  // Committed text
    @State private var displayText = ""  // Display text (updated during IME input)
    @State private var editingPosition: CGPoint = .zero  // Display coordinates
    @State private var editingImagePosition: CGPoint = .zero  // Image coordinates (fixed for expansion)
    @State private var editingAnnotationId: UUID?  // Editing text annotation ID (nil for new)
    @State private var isDraggingAnnotation = false
    @State private var isResizingAnnotation = false
    @State private var activeResizeHandle: ResizeHandle?
    @State private var dragStartPoint: CGPoint = .zero
    @State private var lastClickTime: Date = .distantPast
    @State private var lastClickPoint: CGPoint = .zero
    @State private var pendingSelectAnnotationId: UUID?  // Click selection for drawing tools
    @FocusState private var isTextFieldFocused: Bool

    var body: some View {
        ZStack {
            Canvas { context, size in
                let scale = CGSize(
                    width: expandedSize.width / canvasSize.width,
                    height: expandedSize.height / canvasSize.height
                )

                for annotation in viewModel.annotations {
                    // Mosaic is already applied in compositeImage, so skip
                    if annotation.type != .mosaic {
                        drawAnnotation(annotation, context: &context, scale: scale)
                    }

                    // Draw frame for selected annotation
                    if annotation.id == viewModel.selectedAnnotationId {
                        drawSelectionIndicator(for: annotation, context: &context, scale: scale)
                    }
                }

                if let current = viewModel.getCurrentAnnotation() {
                    drawAnnotation(current, context: &context, scale: scale)
                }

                // Draw the crop overlay
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
                // Calculate display scale
                let displayScale = canvasSize.height / expandedSize.height
                let scaledFontSize = viewModel.fontSize * displayScale
                // Dynamic display position from image coordinates (tracks expansion)
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
                            // Outline text (white) - uses displayText
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

                            // IME-aware input field
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
            // Commit IME when switching tools during text editing
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
        // End editing when clicking elsewhere during text input
        if isEditing {
            // Remove focus to commit pending IME text
            if let window = NSApp.keyWindow {
                window.makeFirstResponder(nil)
            }
            // finishTextEditing is called from controlTextDidEndEditing
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

        // Drag start
        if viewModel.getCurrentAnnotation() == nil && !isDraggingAnnotation && !isResizingAnnotation {
            if viewModel.selectedTool == .select {
                // Detect double-click
                let now = Date()
                let clickInterval = now.timeIntervalSince(lastClickTime)
                let clickDistance = hypot(value.startLocation.x - lastClickPoint.x, value.startLocation.y - lastClickPoint.y)
                let isDoubleClick = clickInterval < 0.3 && clickDistance < 10

                lastClickTime = now
                lastClickPoint = value.startLocation

                // Select tool: select, move, resize
                if let selectedId = viewModel.selectedAnnotationId,
                   let annotation = viewModel.annotations.first(where: { $0.id == selectedId }),
                   let handle = hitTestResizeHandle(annotation: annotation, point: value.startLocation, scale: scale) {
                    // Hit resize handle -> resize mode
                    viewModel.saveStateForUndo()
                    isResizingAnnotation = true
                    activeResizeHandle = handle
                    dragStartPoint = scaledStart
                } else if let hitAnnotation = viewModel.hitTest(at: scaledStart) {
                    // Double-click text annotation -> edit mode
                    if isDoubleClick && hitAnnotation.type == .text {
                        startEditingTextAnnotation(hitAnnotation)
                        return
                    }
                    // Hit existing annotation -> select/move mode
                    viewModel.saveStateForUndo()
                    viewModel.selectAnnotation(id: hitAnnotation.id)
                    isDraggingAnnotation = true
                    dragStartPoint = scaledStart
                } else {
                    // No hit -> deselect
                    viewModel.deselectAnnotation()
                }
            } else if viewModel.selectedTool == .crop {
                // Crop tool: start selecting crop area
                if viewModel.cropRect == nil {
                    viewModel.startCrop(at: scaledStart)
                }
            } else if viewModel.selectedTool == .text {
                // Text tool: click to select existing or start new text
                if let hitAnnotation = viewModel.hitTest(at: scaledStart) {
                    pendingSelectAnnotationId = hitAnnotation.id
                } else {
                    viewModel.deselectAnnotation()
                }
            } else {
                // Drawing tools: click to select existing or create new
                if let hitAnnotation = viewModel.hitTest(at: scaledStart) {
                    // Existing annotation: click selects, drag creates new
                    pendingSelectAnnotationId = hitAnnotation.id
                } else {
                    viewModel.deselectAnnotation()
                    viewModel.startAnnotation(at: scaledStart)
                }
            }
        }

        // If dragging on an existing annotation, switch to creating new after a threshold
        if pendingSelectAnnotationId != nil {
            let dragDistance = hypot(value.location.x - value.startLocation.x, value.location.y - value.startLocation.y)
            if dragDistance > 5 {
                pendingSelectAnnotationId = nil
                viewModel.deselectAnnotation()
                // For the text tool, do not create a new annotation (handleDragEnd starts input)
                if viewModel.selectedTool != .text {
                    viewModel.startAnnotation(at: scaledStart)
                }
            }
        }

        // Dragging
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
            // Update crop area
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
            // Click selects existing annotation
            pendingSelectAnnotationId = nil
            viewModel.selectAnnotation(id: annotationId)
            viewModel.selectedTool = .select
        } else if isResizingAnnotation {
            // Resize complete
            isResizingAnnotation = false
            activeResizeHandle = nil
        } else if isDraggingAnnotation {
            // Move complete
            isDraggingAnnotation = false
        } else if viewModel.selectedTool == .text {
            editingPosition = value.location
            // Keep image coordinates fixed (unaffected by expansion offset changes)
            editingImagePosition = scaledEnd
            isEditing = true
            // Set initial bounds (empty text)
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

        let handleSize: CGFloat = 16  // Larger size for hit testing

        // For arrows, only startPoint and endPoint
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
            // For rectangle/mosaic/text, use all four corners
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
        // editingImagePosition uses the fixed image coordinates from edit start
        // (unaffected by expansion-related imageOffset changes)
        viewModel.editingTextBounds = Annotation.computeTextBounds(
            text: text,
            fontSize: viewModel.fontSize,
            origin: editingImagePosition
        )
    }

    private func finishTextEditing() {
        // Use displayText (latest input)
        let finalText = displayText

        defer {
            isEditing = false
            editingText = ""
            displayText = ""
            editingAnnotationId = nil
        }

        guard !finalText.isEmpty else {
            // If empty, delete the previously edited annotation
            if let annotationId = editingAnnotationId {
                viewModel.deleteAnnotation(id: annotationId)
            }
            return
        }

        if let annotationId = editingAnnotationId {
            // Update existing annotation
            viewModel.updateTextAnnotation(id: annotationId, text: finalText)
        } else {
            // Create new (editingImagePosition is fixed at edit start)
            viewModel.addTextAnnotation(at: editingImagePosition, text: finalText)
        }
    }

    private func startEditingTextAnnotation(_ annotation: Annotation) {
        guard annotation.type == .text, let text = annotation.text else { return }

        let scale = CGSize(
            width: expandedSize.width / canvasSize.width,
            height: expandedSize.height / canvasSize.height
        )

        // Convert from image coordinates to canvas coordinates (add imageOffset)
        editingPosition = CGPoint(
            x: (annotation.endPoint.x + imageOffset.x) / scale.width,
            y: (annotation.endPoint.y + imageOffset.y) / scale.height
        )
        // Keep image coordinates fixed
        editingImagePosition = annotation.endPoint
        editingText = text
        displayText = text
        editingAnnotationId = annotation.id
        isEditing = true
        // Set bounds for the editing text
        updateEditingTextBounds(text: text)

        // Deselect while editing
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
                // Scale font size to display scale
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
        // White outline
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

        // Main text
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
            // For arrows, use a rectangle that includes start and end points
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
            // Text is drawn at display scale, so scale bounds as well
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

        // Draw handles
        let handleSize: CGFloat = 8
        let handles: [CGPoint]

        if annotation.type == .arrow {
            // For arrows, only startPoint and endPoint
            handles = [displayStart, displayEnd]
        } else {
            // For rectangle/mosaic/text, use all four corners
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
        // Convert from image coordinates to canvas coordinates (add imageOffset)
        let displayRect = CGRect(
            x: (cropRect.origin.x + imageOffset.x) / scale.width,
            y: (cropRect.origin.y + imageOffset.y) / scale.height,
            width: cropRect.width / scale.width,
            height: cropRect.height / scale.height
        )

        // Overlay that dims the outside area
        let dimColor = Color.black.opacity(0.5)

        // Top
        if displayRect.minY > 0 {
            let topRect = CGRect(x: 0, y: 0, width: canvasSize.width, height: displayRect.minY)
            context.fill(Path(topRect), with: .color(dimColor))
        }

        // Bottom
        if displayRect.maxY < canvasSize.height {
            let bottomRect = CGRect(x: 0, y: displayRect.maxY, width: canvasSize.width, height: canvasSize.height - displayRect.maxY)
            context.fill(Path(bottomRect), with: .color(dimColor))
        }

        // Left
        if displayRect.minX > 0 {
            let leftRect = CGRect(x: 0, y: displayRect.minY, width: displayRect.minX, height: displayRect.height)
            context.fill(Path(leftRect), with: .color(dimColor))
        }

        // Right
        if displayRect.maxX < canvasSize.width {
            let rightRect = CGRect(x: displayRect.maxX, y: displayRect.minY, width: canvasSize.width - displayRect.maxX, height: displayRect.height)
            context.fill(Path(rightRect), with: .color(dimColor))
        }

        // Crop area border
        let borderPath = Path(displayRect)
        context.stroke(borderPath, with: .color(.white), lineWidth: 2)

        // Corner handles
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
