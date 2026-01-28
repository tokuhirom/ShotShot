import SwiftUI

struct SettingsView: View {
    @State private var viewModel = SettingsViewModel()

    var body: some View {
        TabView {
            GeneralSettingsView(viewModel: viewModel)
                .tabItem {
                    Label("一般", systemImage: "gear")
                }

            HotkeySettingsView(viewModel: viewModel)
                .tabItem {
                    Label("ショートカット", systemImage: "keyboard")
                }
        }
        .frame(minWidth: 400, minHeight: 200)
    }
}

struct GeneralSettingsView: View {
    @Bindable var viewModel: SettingsViewModel

    var body: some View {
        Form {
            Section {
                HStack {
                    TextField("保存先", text: $viewModel.savePath)
                        .textFieldStyle(.roundedBorder)

                    Button("選択...") {
                        viewModel.selectSaveDirectory()
                    }
                }

                Toggle("保存時にクリップボードにもコピー", isOn: $viewModel.copyToClipboard)
            }
        }
        .padding()
    }
}

struct HotkeySettingsView: View {
    @Bindable var viewModel: SettingsViewModel

    var body: some View {
        Form {
            Section("キャプチャのショートカット") {
                VStack(alignment: .leading, spacing: 12) {
                    // 修飾キー（2行に分けて配置）
                    VStack(alignment: .leading, spacing: 8) {
                        Text("修飾キー:")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        HStack(spacing: 16) {
                            Toggle("⌃ Control", isOn: $viewModel.useControl)
                                .toggleStyle(.checkbox)
                            Toggle("⇧ Shift", isOn: $viewModel.useShift)
                                .toggleStyle(.checkbox)
                        }
                        HStack(spacing: 16) {
                            Toggle("⌥ Option", isOn: $viewModel.useOption)
                                .toggleStyle(.checkbox)
                            Toggle("⌘ Command", isOn: $viewModel.useCommand)
                                .toggleStyle(.checkbox)
                        }
                    }

                    Divider()

                    // キー入力
                    HStack {
                        Text("キー:")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        TextField("", text: $viewModel.hotkeyKey)
                            .frame(width: 50)
                            .textFieldStyle(.roundedBorder)

                        Text("(例: 4, S, A など)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    // 現在のショートカット表示
                    HStack {
                        Text("現在:")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text(viewModel.currentHotkeyDisplay)
                            .font(.system(.body, design: .monospaced))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.secondary.opacity(0.1))
                            .cornerRadius(4)
                    }

                    Divider()

                    HStack {
                        Button("ホットキーを更新") {
                            viewModel.updateHotkey()
                        }
                        .buttonStyle(.borderedProminent)

                        if !viewModel.hotkeyStatus.isEmpty {
                            Text(viewModel.hotkeyStatus)
                                .foregroundColor(viewModel.hotkeyStatusIsError ? .red : .green)
                                .font(.caption)
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

#Preview {
    SettingsView()
}
