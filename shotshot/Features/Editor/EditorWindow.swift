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
    }

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

            ColorPicker("", selection: $viewModel.selectedColorBinding)
                .labelsHidden()
                .frame(width: 30)

            Slider(value: $viewModel.lineWidth, in: 1...20)
                .frame(width: 100)

            Spacer()

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

enum ToolType: CaseIterable {
    case arrow
    case text
    case mosaic

    var iconName: String {
        switch self {
        case .arrow: return "arrow.up.right"
        case .text: return "textformat"
        case .mosaic: return "square.grid.3x3"
        }
    }

    var displayName: String {
        switch self {
        case .arrow: return "矢印"
        case .text: return "テキスト"
        case .mosaic: return "モザイク"
        }
    }
}
