import AppKit
import SwiftUI

struct EditorWindow: View {
    @Bindable var viewModel: EditorViewModel

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            editorContent
            bottomBar
        }
        .frame(minWidth: 600, minHeight: 400)
        // キーボードショートカット
        .background(
            Group {
                // ⌘Z: Undo
                Button("") { viewModel.undo() }
                    .keyboardShortcut("z", modifiers: .command)
                    .opacity(0)
                // ⇧⌘Z: Redo
                Button("") { viewModel.redo() }
                    .keyboardShortcut("z", modifiers: [.command, .shift])
                    .opacity(0)
                // Delete: 選択中の注釈を削除
                Button("") { viewModel.deleteSelectedAnnotation() }
                    .keyboardShortcut(.delete, modifiers: [])
                    .opacity(0)
            }
        )
    }

    private static let presetColors: [NSColor] = [
        NSColor(red: 0.98, green: 0.22, blue: 0.53, alpha: 1.0), // Skitch Pink
        NSColor(red: 1.0, green: 0.23, blue: 0.19, alpha: 1.0),  // Red
        NSColor(red: 1.0, green: 0.58, blue: 0.0, alpha: 1.0),   // Orange
        NSColor(red: 1.0, green: 0.8, blue: 0.0, alpha: 1.0),    // Yellow
        NSColor(red: 0.3, green: 0.85, blue: 0.39, alpha: 1.0),  // Green
        NSColor(red: 0.0, green: 0.48, blue: 1.0, alpha: 1.0),   // Blue
    ]

    private var toolbar: some View {
        HStack(spacing: 12) {
            ForEach(ToolType.allCases, id: \.self) { tool in
                ToolButton(
                    tool: tool,
                    isSelected: viewModel.selectedTool == tool,
                    action: { viewModel.selectedTool = tool }
                )
            }

            Divider()
                .frame(height: 24)

            // Preset color buttons
            HStack(spacing: 4) {
                ForEach(0..<Self.presetColors.count, id: \.self) { index in
                    let color = Self.presetColors[index]
                    ColorButton(
                        color: color,
                        isSelected: viewModel.selectedColor == color,
                        action: { viewModel.selectedColor = color }
                    )
                }

                // Custom color picker
                ColorPicker("", selection: $viewModel.selectedColorBinding)
                    .labelsHidden()
                    .frame(width: 24, height: 24)
            }

            Divider()
                .frame(height: 24)

            Slider(value: $viewModel.lineWidth, in: 1...20)
                .frame(width: 100)

            Spacer()

            // Undo/Redo buttons
            HStack(spacing: 4) {
                Button(action: { viewModel.undo() }) {
                    Image(systemName: "arrow.uturn.backward")
                        .font(.title3)
                }
                .buttonStyle(.bordered)
                .disabled(!viewModel.canUndo)
                .help("取り消し (⌘Z)")

                Button(action: { viewModel.redo() }) {
                    Image(systemName: "arrow.uturn.forward")
                        .font(.title3)
                }
                .buttonStyle(.bordered)
                .disabled(!viewModel.canRedo)
                .help("やり直し (⇧⌘Z)")
            }

            Divider()
                .frame(height: 24)

            Button("クリア") {
                viewModel.clearAnnotations()
            }
            .buttonStyle(.bordered)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var editorContent: some View {
        GeometryReader { geometry in
            ZStack {
                Color(nsColor: .controlBackgroundColor)

                let imageSize = viewModel.screenshot.image.size
                let scaledSize = scaledImageSize(imageSize: imageSize, containerSize: geometry.size)

                ZStack {
                    Image(nsImage: viewModel.compositeImage)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: scaledSize.width, height: scaledSize.height)

                    AnnotationCanvas(
                        viewModel: viewModel,
                        canvasSize: scaledSize,
                        imageSize: imageSize
                    )
                    .frame(width: scaledSize.width, height: scaledSize.height)
                }
            }
        }
    }

    private var bottomBar: some View {
        HStack {
            Text(viewModel.statusMessage)
                .foregroundColor(.secondary)
                .font(.caption)

            Spacer()

            Button("キャンセル") {
                viewModel.cancel()
            }
            .buttonStyle(.bordered)
            .keyboardShortcut(.escape, modifiers: [])

            Button("Done") {
                viewModel.done()
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.return, modifiers: [])
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private func scaledImageSize(imageSize: NSSize, containerSize: CGSize) -> CGSize {
        let widthRatio = containerSize.width / imageSize.width
        let heightRatio = containerSize.height / imageSize.height
        let ratio = min(widthRatio, heightRatio, 1.0)

        return CGSize(
            width: imageSize.width * ratio,
            height: imageSize.height * ratio
        )
    }
}

struct ToolButton: View {
    let tool: ToolType
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: tool.iconName)
                .font(.title2)
                .frame(width: 32, height: 32)
                .background(isSelected ? Color.accentColor.opacity(0.2) : Color.clear)
                .cornerRadius(6)
        }
        .buttonStyle(.plain)
        .help(tool.displayName)
    }
}

struct ColorButton: View {
    let color: NSColor
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Circle()
                .fill(Color(nsColor: color))
                .frame(width: 24, height: 24)
                .overlay(
                    Circle()
                        .strokeBorder(isSelected ? Color.primary : Color.clear, lineWidth: 2)
                )
                .overlay(
                    Circle()
                        .strokeBorder(Color.primary.opacity(0.2), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }
}

enum ToolType: CaseIterable {
    case arrow
    case rectangle
    case text
    case mosaic

    var iconName: String {
        switch self {
        case .arrow: return "arrow.up.right"
        case .rectangle: return "rectangle"
        case .text: return "textformat"
        case .mosaic: return "checkerboard.rectangle"
        }
    }

    var displayName: String {
        switch self {
        case .arrow: return "矢印"
        case .rectangle: return "四角"
        case .text: return "テキスト"
        case .mosaic: return "モザイク"
        }
    }
}
