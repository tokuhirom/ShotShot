import AppKit
import Carbon
import Foundation
import SwiftUI

extension Notification.Name {
    static let hotkeySettingsChanged = Notification.Name("hotkeySettingsChanged")
}

@Observable
@MainActor
final class SettingsViewModel {
    private let settings = AppSettings.shared

    var savePath: String {
        didSet { settings.savePath = savePath }
    }

    var copyToClipboard: Bool {
        didSet { settings.copyToClipboard = copyToClipboard }
    }

    var useControl: Bool = true
    var useShift: Bool = true
    var useOption: Bool = false
    var useCommand: Bool = false
    var hotkeyKey: String = "4"

    var hotkeyStatus: String = ""
    var hotkeyStatusIsError: Bool = false

    var currentHotkeyDisplay: String {
        var parts: [String] = []
        if useControl { parts.append("⌃") }
        if useShift { parts.append("⇧") }
        if useOption { parts.append("⌥") }
        if useCommand { parts.append("⌘") }
        parts.append(hotkeyKey.uppercased())
        return parts.joined()
    }

    init() {
        self.savePath = settings.savePath
        self.copyToClipboard = settings.copyToClipboard

        let modifiers = settings.hotkeyModifiers
        self.useControl = modifiers & UInt32(NSEvent.ModifierFlags.control.rawValue) != 0
        self.useShift = modifiers & UInt32(NSEvent.ModifierFlags.shift.rawValue) != 0
        self.useOption = modifiers & UInt32(NSEvent.ModifierFlags.option.rawValue) != 0
        self.useCommand = modifiers & UInt32(NSEvent.ModifierFlags.command.rawValue) != 0

        if let keyCode = keyCodeToString(settings.hotkeyKeyCode) {
            self.hotkeyKey = keyCode
        }
    }

    func selectSaveDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true

        if panel.runModal() == .OK, let url = panel.url {
            savePath = url.path
        }
    }

    func updateHotkey() {
        var modifiers: UInt32 = 0
        if useControl { modifiers |= UInt32(NSEvent.ModifierFlags.control.rawValue) }
        if useShift { modifiers |= UInt32(NSEvent.ModifierFlags.shift.rawValue) }
        if useOption { modifiers |= UInt32(NSEvent.ModifierFlags.option.rawValue) }
        if useCommand { modifiers |= UInt32(NSEvent.ModifierFlags.command.rawValue) }

        guard let keyCode = stringToKeyCode(hotkeyKey) else {
            hotkeyStatus = "無効なキーです"
            hotkeyStatusIsError = true
            return
        }

        settings.hotkeyModifiers = modifiers
        settings.hotkeyKeyCode = keyCode

        // Re-register hotkey immediately
        NotificationCenter.default.post(name: .hotkeySettingsChanged, object: nil)

        hotkeyStatus = "ホットキーを更新しました"
        hotkeyStatusIsError = false
    }

    private func keyCodeToString(_ keyCode: UInt32) -> String? {
        let keyMap: [UInt32: String] = [
            0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G", 6: "Z", 7: "X",
            8: "C", 9: "V", 11: "B", 12: "Q", 13: "W", 14: "E", 15: "R",
            16: "Y", 17: "T", 18: "1", 19: "2", 20: "3", 21: "4", 22: "6",
            23: "5", 24: "=", 25: "9", 26: "7", 27: "-", 28: "8", 29: "0",
            31: "O", 32: "U", 34: "I", 35: "P", 37: "L", 38: "J", 40: "K",
            45: "N", 46: "M"
        ]
        return keyMap[keyCode]
    }

    private func stringToKeyCode(_ string: String) -> UInt32? {
        let keyMap: [String: UInt32] = [
            "A": 0, "S": 1, "D": 2, "F": 3, "H": 4, "G": 5, "Z": 6, "X": 7,
            "C": 8, "V": 9, "B": 11, "Q": 12, "W": 13, "E": 14, "R": 15,
            "Y": 16, "T": 17, "1": 18, "2": 19, "3": 20, "4": 21, "6": 22,
            "5": 23, "=": 24, "9": 25, "7": 26, "-": 27, "8": 28, "0": 29,
            "O": 31, "U": 32, "I": 34, "P": 35, "L": 37, "J": 38, "K": 40,
            "N": 45, "M": 46
        ]
        return keyMap[string.uppercased()]
    }
}
