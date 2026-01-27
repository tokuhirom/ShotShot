import Foundation
import SwiftUI

@Observable
@MainActor
final class AppSettings {
    static let shared = AppSettings()

    private let defaults = UserDefaults.standard

    private enum Keys {
        static let savePath = "savePath"
        static let hotkeyModifiers = "hotkeyModifiers"
        static let hotkeyKeyCode = "hotkeyKeyCode"
        static let copyToClipboard = "copyToClipboard"
        static let defaultAnnotationColor = "defaultAnnotationColor"
    }

    var savePath: String {
        didSet { defaults.set(savePath, forKey: Keys.savePath) }
    }

    var hotkeyModifiers: UInt32 {
        didSet { defaults.set(hotkeyModifiers, forKey: Keys.hotkeyModifiers) }
    }

    var hotkeyKeyCode: UInt32 {
        didSet { defaults.set(hotkeyKeyCode, forKey: Keys.hotkeyKeyCode) }
    }

    var copyToClipboard: Bool {
        didSet { defaults.set(copyToClipboard, forKey: Keys.copyToClipboard) }
    }

    private init() {
        let picturesPath = NSSearchPathForDirectoriesInDomains(.picturesDirectory, .userDomainMask, true).first ?? "~/Pictures"
        let defaultSavePath = (picturesPath as NSString).appendingPathComponent("shotshot")

        self.savePath = defaults.string(forKey: Keys.savePath) ?? defaultSavePath
        self.hotkeyModifiers = UInt32(defaults.integer(forKey: Keys.hotkeyModifiers))
        self.hotkeyKeyCode = UInt32(defaults.integer(forKey: Keys.hotkeyKeyCode))
        self.copyToClipboard = defaults.object(forKey: Keys.copyToClipboard) as? Bool ?? true

        if self.hotkeyModifiers == 0 {
            self.hotkeyModifiers = UInt32(NSEvent.ModifierFlags.control.rawValue | NSEvent.ModifierFlags.shift.rawValue)
        }
        if self.hotkeyKeyCode == 0 {
            self.hotkeyKeyCode = 21 // "4" key
        }
    }
}
