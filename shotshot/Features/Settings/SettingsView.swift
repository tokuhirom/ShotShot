import SwiftUI

struct SettingsView: View {
    @State private var viewModel = SettingsViewModel()

    var body: some View {
        TabView {
            GeneralSettingsView(viewModel: viewModel)
                .tabItem {
                    Label("settings.tab.general", systemImage: "gear")
                }

            HotkeySettingsView(viewModel: viewModel)
                .tabItem {
                    Label("settings.tab.shortcuts", systemImage: "keyboard")
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
                    TextField("settings.save_path", text: $viewModel.savePath)
                        .textFieldStyle(.roundedBorder)

                    Button("settings.choose") {
                        viewModel.selectSaveDirectory()
                    }
                }

                Toggle("settings.copy_to_clipboard", isOn: $viewModel.copyToClipboard)

                HStack {
                    Text("settings.timer_seconds")
                    Stepper(value: $viewModel.timerSeconds, in: 1...10) {
                        let format = NSLocalizedString("settings.timer_seconds_value_format", comment: "")
                        Text(String.localizedStringWithFormat(format, viewModel.timerSeconds))
                            .monospacedDigit()
                    }
                }
            }
        }
        .padding()
    }
}

struct HotkeySettingsView: View {
    @Bindable var viewModel: SettingsViewModel

    var body: some View {
        Form {
            Section("settings.shortcuts_section") {
                VStack(alignment: .leading, spacing: 12) {
                    // Modifier keys (split into two rows)
                    VStack(alignment: .leading, spacing: 8) {
                        Text("settings.modifier_keys")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        HStack(spacing: 16) {
                            Toggle("settings.modifier.control", isOn: $viewModel.useControl)
                                .toggleStyle(.checkbox)
                            Toggle("settings.modifier.shift", isOn: $viewModel.useShift)
                                .toggleStyle(.checkbox)
                        }
                        HStack(spacing: 16) {
                            Toggle("settings.modifier.option", isOn: $viewModel.useOption)
                                .toggleStyle(.checkbox)
                            Toggle("settings.modifier.command", isOn: $viewModel.useCommand)
                                .toggleStyle(.checkbox)
                        }
                    }

                    Divider()

                    // Key input
                    HStack {
                        Text("settings.key")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        TextField("", text: $viewModel.hotkeyKey)
                            .frame(width: 50)
                            .textFieldStyle(.roundedBorder)

                        Text("settings.key_example")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    // Current shortcut display
                    HStack {
                        Text("settings.current")
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
                        Button("settings.update_hotkey") {
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
