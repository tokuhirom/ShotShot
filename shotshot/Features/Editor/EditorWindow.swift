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

    private static let presetColors: [(String, NSColor)] = [
        ("ピンク", NSColor(red: 0.98, green: 0.22, blue: 0.53, alpha: 1.0)),
        ("赤", NSColor(red: 1.0, green: 0.23, blue: 0.19, alpha: 1.0)),
        ("オレンジ", NSColor(red: 1.0, green: 0.58, blue: 0.0, alpha: 1.0)),
        ("黄", NSColor(red: 1.0, green: 0.8, blue: 0.0, alpha: 1.0)),
        ("緑", NSColor(red: 0.3, green: 0.85, blue: 0.39, alpha: 1.0)),
        ("青", NSColor(red: 0.0, green: 0.48, blue: 1.0, alpha: 1.0)),
        ("白", NSColor.white),
        ("黒", NSColor.black),
    ]

    private static let fontSizes: [CGFloat] = [16, 24, 32, 48, 64, 80, 96]

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

            // 色選択ボタン（Popover）
            ColorPickerButton(selectedColor: $viewModel.selectedColor, presetColors: Self.presetColors)

            Divider()
                .frame(height: 24)

            // ツールごとのオプション
            if viewModel.selectedTool == .text {
                // テキスト: フォントサイズ
                Menu {
                    ForEach(Self.fontSizes, id: \.self) { size in
                        Button("\(Int(size)) pt") {
                            viewModel.fontSize = size
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text("\(Int(viewModel.fontSize)) pt")
                            .monospacedDigit()
                        Image(systemName: "chevron.down")
                            .font(.caption)
                    }
                }
                .menuStyle(.borderlessButton)
                .frame(width: 70)
            } else if viewModel.selectedTool == .rectangle {
                // 四角: 角丸/角張り切り替え + 線幅
                HStack(spacing: 8) {
                    Button(action: { viewModel.useRoundedCorners.toggle() }) {
                        Image(systemName: viewModel.useRoundedCorners ? "rectangle.roundedtop" : "rectangle")
                            .font(.title2)
                            .frame(width: 28, height: 28)
                    }
                    .buttonStyle(.bordered)
                    .help(viewModel.useRoundedCorners ? "角丸" : "角張り")

                    HStack(spacing: 4) {
                        Text("太さ")
                            .font(.caption)
                        Slider(value: $viewModel.lineWidth, in: 1...20)
                            .frame(width: 80)
                    }
                }
            } else if viewModel.selectedTool == .crop {
                // クロップ: 適用/キャンセルボタン
                HStack(spacing: 8) {
                    if viewModel.cropRect != nil {
                        Button("適用") {
                            viewModel.applyCrop()
                        }
                        .buttonStyle(.borderedProminent)

                        Button("キャンセル") {
                            viewModel.cancelCrop()
                        }
                        .buttonStyle(.bordered)
                    } else {
                        Text("ドラッグして切り抜き領域を選択")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            } else if viewModel.selectedTool == .select {
                // 選択ツール: 何も表示しない
                EmptyView()
            } else {
                // その他: 線幅のみ
                HStack(spacing: 4) {
                    Text("太さ")
                        .font(.caption)
                    Slider(value: $viewModel.lineWidth, in: 1...20)
                        .frame(width: 80)
                }
            }

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

struct ColorSwatch: View {
    let color: NSColor
    let size: CGFloat

    var body: some View {
        ZStack {
            // 白い縁取り
            Circle()
                .fill(Color.white)
                .frame(width: size, height: size)
            // メインカラー
            Circle()
                .fill(Color(nsColor: color))
                .frame(width: size - 3, height: size - 3)
        }
        .overlay(
            Circle()
                .strokeBorder(Color.black.opacity(0.2), lineWidth: 0.5)
        )
    }
}

struct ColorPickerButton: View {
    @Binding var selectedColor: NSColor
    let presetColors: [(String, NSColor)]
    @State private var showPopover = false

    var body: some View {
        Button(action: { showPopover.toggle() }) {
            HStack(spacing: 4) {
                ZStack {
                    Circle()
                        .fill(Color.white)
                        .frame(width: 22, height: 22)
                    Circle()
                        .fill(Color(nsColor: selectedColor))
                        .frame(width: 18, height: 18)
                }
                .overlay(Circle().strokeBorder(Color.black.opacity(0.2), lineWidth: 0.5))
                Image(systemName: "chevron.down")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }
        }
        .buttonStyle(.plain)
        .popover(isPresented: $showPopover, arrowEdge: .bottom) {
            VStack(spacing: 8) {
                // 色グリッド (4x2)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 28))], spacing: 6) {
                    ForEach(0..<presetColors.count, id: \.self) { index in
                        let (_, color) = presetColors[index]
                        Button(action: {
                            selectedColor = color
                            showPopover = false
                        }) {
                            ZStack {
                                Circle()
                                    .fill(Color.white)
                                    .frame(width: 26, height: 26)
                                Circle()
                                    .fill(Color(nsColor: color))
                                    .frame(width: 22, height: 22)
                                if selectedColor.isEqual(to: color) {
                                    Circle()
                                        .strokeBorder(Color.accentColor, lineWidth: 2)
                                        .frame(width: 28, height: 28)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }

                Divider()

                // カスタムカラーピッカー
                ColorPicker("カスタム色", selection: Binding(
                    get: { Color(nsColor: selectedColor) },
                    set: { selectedColor = NSColor($0) }
                ))
                .labelsHidden()
            }
            .padding(10)
            .frame(width: 140)
        }
    }
}

enum ToolType: CaseIterable {
    case select
    case crop
    case arrow
    case rectangle
    case text
    case mosaic

    var name: String {
        switch self {
        case .select: return "select"
        case .crop: return "crop"
        case .arrow: return "arrow"
        case .rectangle: return "rectangle"
        case .text: return "text"
        case .mosaic: return "mosaic"
        }
    }

    static func from(name: String) -> ToolType {
        switch name {
        case "select": return .select
        case "crop": return .crop
        case "arrow": return .arrow
        case "rectangle": return .rectangle
        case "text": return .text
        case "mosaic": return .mosaic
        default: return .select
        }
    }

    var iconName: String {
        switch self {
        case .select: return "arrow.up.left"
        case .crop: return "crop"
        case .arrow: return "arrow.up.right"
        case .rectangle: return "rectangle"
        case .text: return "textformat"
        case .mosaic: return "checkerboard.rectangle"
        }
    }

    var displayName: String {
        switch self {
        case .select: return "選択"
        case .crop: return "切り抜き"
        case .arrow: return "矢印"
        case .rectangle: return "四角"
        case .text: return "テキスト"
        case .mosaic: return "モザイク"
        }
    }
}
