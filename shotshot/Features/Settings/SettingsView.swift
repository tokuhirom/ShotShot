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
        .frame(width: 450, height: 250)
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
            Section {
                HStack {
                    Text("キャプチャ:")

                    HStack(spacing: 4) {
                        Toggle("Control", isOn: $viewModel.useControl)
                            .toggleStyle(.checkbox)
                        Toggle("Shift", isOn: $viewModel.useShift)
                            .toggleStyle(.checkbox)
                        Toggle("Option", isOn: $viewModel.useOption)
                            .toggleStyle(.checkbox)
                        Toggle("Command", isOn: $viewModel.useCommand)
                            .toggleStyle(.checkbox)
                    }

                    Text("+")

                    TextField("キー", text: $viewModel.hotkeyKey)
                        .frame(width: 40)
                        .textFieldStyle(.roundedBorder)
                }

                Button("ホットキーを更新") {
                    viewModel.updateHotkey()
                }

                if !viewModel.hotkeyStatus.isEmpty {
                    Text(viewModel.hotkeyStatus)
                        .foregroundColor(viewModel.hotkeyStatusIsError ? .red : .green)
                        .font(.caption)
                }
            }
        }
        .padding()
    }
}

#Preview {
    SettingsView()
}
