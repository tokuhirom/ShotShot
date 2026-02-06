import AppKit
import SwiftUI

struct EditorWindow: View {
    @Bindable var viewModel: EditorViewModel
    @State private var displayScale: CGFloat = 1.0
    @State private var isUserZooming: Bool = false

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            editorContent
            bottomBar
        }
        .frame(minWidth: 600, minHeight: 400)
        // Keyboard shortcuts
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
                // ⌘C: Copy to clipboard
                Button("") { viewModel.copyToClipboard() }
                    .keyboardShortcut("c", modifiers: .command)
                    .opacity(0)
                // ⌘S: Save As
                Button("") { viewModel.saveAs() }
                    .keyboardShortcut("s", modifiers: .command)
                    .opacity(0)
                // Delete: Delete selected annotation
                Button("") { viewModel.deleteSelectedAnnotation() }
                    .keyboardShortcut(.delete, modifiers: [])
                    .opacity(0)
                // ⌘+: Zoom in
                Button("") { zoomIn() }
                    .keyboardShortcut("=", modifiers: .command)
                    .opacity(0)
                // ⇧⌘+: Zoom in (some keyboard layouts send Shift+="")
                Button("") { zoomIn() }
                    .keyboardShortcut("=", modifiers: [.command, .shift])
                    .opacity(0)
                // ⌘-: Zoom out
                Button("") { zoomOut() }
                    .keyboardShortcut("-", modifiers: .command)
                    .opacity(0)
                // ⌘0: Zoom reset (100%)
                Button("") { resetZoom() }
                    .keyboardShortcut("0", modifiers: .command)
                    .opacity(0)
            }
        )
    }

    private static let presetColors: [(String, NSColor)] = [
        (NSLocalizedString("editor.color.pink", comment: ""), NSColor(red: 0.98, green: 0.22, blue: 0.53, alpha: 1.0)),
        (NSLocalizedString("editor.color.red", comment: ""), NSColor(red: 1.0, green: 0.23, blue: 0.19, alpha: 1.0)),
        (NSLocalizedString("editor.color.orange", comment: ""), NSColor(red: 1.0, green: 0.58, blue: 0.0, alpha: 1.0)),
        (NSLocalizedString("editor.color.yellow", comment: ""), NSColor(red: 1.0, green: 0.8, blue: 0.0, alpha: 1.0)),
        (NSLocalizedString("editor.color.green", comment: ""), NSColor(red: 0.3, green: 0.85, blue: 0.39, alpha: 1.0)),
        (NSLocalizedString("editor.color.blue", comment: ""), NSColor(red: 0.0, green: 0.48, blue: 1.0, alpha: 1.0)),
        (NSLocalizedString("editor.color.white", comment: ""), NSColor.white),
        (NSLocalizedString("editor.color.black", comment: ""), NSColor.black)
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

            // Color picker button (popover)
            ColorPickerButton(selectedColor: $viewModel.selectedColor, presetColors: Self.presetColors)

            Divider()
                .frame(height: 24)

            // Tool-specific options
            if viewModel.selectedTool == .text {
                // Text: font size
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
                // Rectangle: rounded/square toggle + line width
                HStack(spacing: 8) {
                    Button(action: { viewModel.useRoundedCorners.toggle() }) {
                        Image(systemName: viewModel.useRoundedCorners ? "rectangle.roundedtop" : "rectangle")
                            .font(.title2)
                            .frame(width: 28, height: 28)
                    }
                    .buttonStyle(.bordered)
                    .help(viewModel.useRoundedCorners
                        ? NSLocalizedString("editor.rounded", comment: "")
                        : NSLocalizedString("editor.square", comment: ""))

                    HStack(spacing: 4) {
                        Text("editor.line_width")
                            .font(.caption)
                        Slider(value: $viewModel.lineWidth, in: 1...20)
                            .frame(width: 80)
                    }
                }
            } else if viewModel.selectedTool == .crop {
                // Crop: apply/cancel buttons
                HStack(spacing: 8) {
                    if viewModel.cropRect != nil {
                        Button("editor.apply_crop") {
                            viewModel.applyCrop()
                        }
                        .buttonStyle(.borderedProminent)

                        Button("common.cancel") {
                            viewModel.cancelCrop()
                        }
                        .buttonStyle(.bordered)
                    } else {
                        Text("editor.crop_drag_hint")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            } else if viewModel.selectedTool == .select {
                // Select tool: show nothing
                EmptyView()
            } else if viewModel.selectedTool == .mosaic {
                // Mosaic: type selection
                HStack(spacing: 8) {
                    ForEach(MosaicType.allCases, id: \.self) { type in
                        Button(action: { viewModel.mosaicType = type }) {
                            VStack(spacing: 2) {
                                Image(systemName: type.iconName)
                                    .font(.title3)
                                Text(type.displayName)
                                    .font(.system(size: 9))
                            }
                            .frame(width: 60, height: 40)
                            .background(
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(viewModel.mosaicType == type ? Color.accentColor.opacity(0.2) : Color.secondary.opacity(0.1))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .stroke(viewModel.mosaicType == type ? Color.accentColor : Color.secondary.opacity(0.3), lineWidth: 1)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            } else {
                // Others: line width only
                HStack(spacing: 4) {
                    Text("editor.line_width")
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
                .help(NSLocalizedString("editor.undo_help", comment: ""))

                Button(action: { viewModel.redo() }) {
                    Image(systemName: "arrow.uturn.forward")
                        .font(.title3)
                }
                .buttonStyle(.bordered)
                .disabled(!viewModel.canRedo)
                .help(NSLocalizedString("editor.redo_help", comment: ""))
            }

            Divider()
                .frame(height: 24)

            Button("editor.clear_annotations") {
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

                let expandedSize = viewModel.expandedImageSize
                let imageSize = viewModel.screenshot.image.size
                let offset = viewModel.imageOffset
                let fitScaleValue = fitScale(imageSize: expandedSize, containerSize: geometry.size)
                let effectiveScale = isUserZooming ? displayScale : fitScaleValue
                let scaledSize = CGSize(
                    width: expandedSize.width * effectiveScale,
                    height: expandedSize.height * effectiveScale
                )

                ScrollView([.horizontal, .vertical]) {
                    ZStack(alignment: .topLeading) {
                        // White background (entire expanded area)
                        Color.white
                            .frame(width: scaledSize.width, height: scaledSize.height)

                        // Place the source image at the offset position
                        Image(nsImage: viewModel.compositeImage)
                            .resizable()
                            .frame(
                                width: imageSize.width * effectiveScale,
                                height: imageSize.height * effectiveScale
                            )
                            .offset(
                                x: offset.x * effectiveScale,
                                y: offset.y * effectiveScale
                            )

                        // Annotation canvas (full size)
                        AnnotationCanvas(
                            viewModel: viewModel,
                            canvasSize: scaledSize,
                            expandedSize: expandedSize,
                            imageOffset: offset
                        )
                        .frame(width: scaledSize.width, height: scaledSize.height)
                    }
                    .frame(width: scaledSize.width, height: scaledSize.height)
                    .frame(
                        minWidth: geometry.size.width,
                        minHeight: geometry.size.height,
                        alignment: .center
                    )
                }
                .onAppear {
                    displayScale = fitScaleValue
                    isUserZooming = false
                }
                .onChange(of: geometry.size) { _, _ in
                    if !isUserZooming {
                        displayScale = fitScaleValue
                    }
                }
                .onChange(of: expandedSize) { _, _ in
                    if !isUserZooming {
                        displayScale = fitScaleValue
                    }
                }
            }
        }
    }

    private var bottomBar: some View {
        HStack {
            // Zoom display
            Text("\(Int(displayScale * 100))%")
                .foregroundColor(.secondary)
                .font(.caption)
                .monospacedDigit()
                .frame(width: 56, alignment: .leading)

            HStack(spacing: 6) {
                Button(action: { zoomOut() }) {
                    Image(systemName: "minus.magnifyingglass")
                }
                .buttonStyle(.bordered)
                .accessibilityLabel(Text("editor.zoom_out"))

                Slider(
                    value: zoomBinding,
                    in: zoomRange
                ) {
                    Text("editor.zoom")
                }
                .labelsHidden()
                .frame(width: 140)

                Button(action: { zoomIn() }) {
                    Image(systemName: "plus.magnifyingglass")
                }
                .buttonStyle(.bordered)
                .accessibilityLabel(Text("editor.zoom_in"))
            }

            Text(viewModel.statusMessage)
                .foregroundColor(.secondary)
                .font(.caption)

            Spacer()

            Button("common.cancel") {
                viewModel.cancel()
            }
            .buttonStyle(.bordered)

            Button("common.done") {
                viewModel.done()
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var zoomRange: ClosedRange<CGFloat> { 0.01...4.0 }
    private var zoomStep: CGFloat { 0.1 }

    private var zoomBinding: Binding<CGFloat> {
        Binding(
            get: { displayScale },
            set: { updateDisplayScale($0) }
        )
    }

    private func fitScale(imageSize: NSSize, containerSize: CGSize) -> CGFloat {
        let widthRatio = containerSize.width / imageSize.width
        let heightRatio = containerSize.height / imageSize.height
        return min(widthRatio, heightRatio, 1.0)
    }

    private func clampZoom(_ value: CGFloat) -> CGFloat {
        min(max(value, zoomRange.lowerBound), zoomRange.upperBound)
    }

    private func updateDisplayScale(_ value: CGFloat) {
        displayScale = clampZoom(value)
        isUserZooming = true
    }

    private func zoomIn() {
        updateDisplayScale(displayScale + zoomStep)
    }

    private func zoomOut() {
        updateDisplayScale(displayScale - zoomStep)
    }

    private func resetZoom() {
        updateDisplayScale(1.0)
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
                .foregroundColor(isSelected ? Color.accentColor : Color.primary)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(isSelected ? Color.accentColor.opacity(0.2) : Color.secondary.opacity(0.1))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(isSelected ? Color.accentColor : Color.secondary.opacity(0.3), lineWidth: 1)
                )
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
            // White outline
            Circle()
                .fill(Color.white)
                .frame(width: size, height: size)
            // Main color
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
                // Color grid (4x2)
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

                // Custom color picker
                ColorPicker("editor.custom_color", selection: Binding(
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
        case .select: return "cursorarrow"
        case .crop: return "crop"
        case .arrow: return "arrow.up.right"
        case .rectangle: return "rectangle"
        case .text: return "textformat"
        case .mosaic: return "checkerboard.rectangle"
        }
    }

    var displayName: String {
        switch self {
        case .select: return NSLocalizedString("tool.select", comment: "")
        case .crop: return NSLocalizedString("tool.crop", comment: "")
        case .arrow: return NSLocalizedString("tool.arrow", comment: "")
        case .rectangle: return NSLocalizedString("tool.rectangle", comment: "")
        case .text: return NSLocalizedString("tool.text", comment: "")
        case .mosaic: return NSLocalizedString("tool.mosaic", comment: "")
        }
    }
}
