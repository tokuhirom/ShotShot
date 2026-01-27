import AppKit
import SwiftUI

struct AnnotationCanvas: View {
    @Bindable var viewModel: EditorViewModel
    let canvasSize: CGSize
    let imageSize: NSSize
    @State private var isEditing = false
    @State private var editingText = ""
    @State private var editingPosition: CGPoint = .zero

    var body: some View {
        ZStack {
            Canvas { context, size in
                let scale = CGSize(
                    width: imageSize.width / canvasSize.width,
                    height: imageSize.height / canvasSize.height
                )

                for annotation in viewModel.annotations {
                    drawAnnotation(annotation, context: &context, scale: scale)
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
                TextField("テキストを入力", text: $editingText, onCommit: {
                    finishTextEditing()
                })
                .textFieldStyle(.plain)
                .font(.system(size: viewModel.fontSize))
                .foregroundColor(Color(nsColor: viewModel.selectedColor))
                .position(editingPosition)
            }
        }
    }

    private func handleDrag(_ value: DragGesture.Value) {
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

        if viewModel.getCurrentAnnotation() == nil {
            viewModel.startAnnotation(at: scaledStart)
        }
        viewModel.updateAnnotation(to: scaledCurrent)
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

        if viewModel.selectedTool == .text {
            editingPosition = value.location
            isEditing = true
        } else {
            viewModel.finishAnnotation(at: scaledEnd)
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

        viewModel.finishAnnotation(at: scaledPosition, text: editingText)
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
        case .text:
            if let text = annotation.text {
                drawText(text, at: displayEnd, color: annotation.color, fontSize: annotation.fontSize ?? 16, context: &context)
            }
        case .mosaic:
            drawMosaicPreview(from: displayStart, to: displayEnd, context: &context)
        }
    }

    private func drawArrow(from start: CGPoint, to end: CGPoint, color: NSColor, lineWidth: CGFloat, context: inout GraphicsContext) {
        var path = Path()
        path.move(to: start)
        path.addLine(to: end)

        context.stroke(path, with: .color(Color(nsColor: color)), lineWidth: lineWidth)

        let angle = atan2(end.y - start.y, end.x - start.x)
        let arrowLength: CGFloat = 15

        let arrowPoint1 = CGPoint(
            x: end.x - arrowLength * cos(angle - .pi / 6),
            y: end.y - arrowLength * sin(angle - .pi / 6)
        )
        let arrowPoint2 = CGPoint(
            x: end.x - arrowLength * cos(angle + .pi / 6),
            y: end.y - arrowLength * sin(angle + .pi / 6)
        )

        var arrowPath = Path()
        arrowPath.move(to: end)
        arrowPath.addLine(to: arrowPoint1)
        arrowPath.move(to: end)
        arrowPath.addLine(to: arrowPoint2)

        context.stroke(arrowPath, with: .color(Color(nsColor: color)), lineWidth: lineWidth)
    }

    private func drawText(_ text: String, at point: CGPoint, color: NSColor, fontSize: CGFloat, context: inout GraphicsContext) {
        let attributedString = AttributedString(text)
        let textView = Text(attributedString)
            .font(.system(size: fontSize))
            .foregroundColor(Color(nsColor: color))

        context.draw(textView, at: point, anchor: .topLeading)
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
}
