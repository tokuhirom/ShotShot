import AppKit
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
        static let timerSeconds = "timerSeconds"
        // Editor settings
        static let selectedTool = "selectedTool"
        static let selectedColorRed = "selectedColorRed"
        static let selectedColorGreen = "selectedColorGreen"
        static let selectedColorBlue = "selectedColorBlue"
        static let selectedColorAlpha = "selectedColorAlpha"
        static let lineWidth = "lineWidth"
        static let fontSize = "fontSize"
        static let useRoundedCorners = "useRoundedCorners"
        static let mosaicType = "mosaicType"
    }

    // Default values
    private static let defaultSkitchPink = NSColor(red: 0.98, green: 0.22, blue: 0.53, alpha: 1.0)

    var savePath: String = "" {
        didSet { defaults.set(savePath, forKey: Keys.savePath) }
    }

    var hotkeyModifiers: UInt32 = 0 {
        didSet { defaults.set(hotkeyModifiers, forKey: Keys.hotkeyModifiers) }
    }

    var hotkeyKeyCode: UInt32 = 0 {
        didSet { defaults.set(hotkeyKeyCode, forKey: Keys.hotkeyKeyCode) }
    }

    var copyToClipboard: Bool = true {
        didSet { defaults.set(copyToClipboard, forKey: Keys.copyToClipboard) }
    }

    var timerSeconds: Int = 3 {
        didSet { defaults.set(timerSeconds, forKey: Keys.timerSeconds) }
    }

    // MARK: - Editor Settings

    var selectedToolName: String = "select" {
        didSet { defaults.set(selectedToolName, forKey: Keys.selectedTool) }
    }

    var selectedColor: NSColor = defaultSkitchPink {
        didSet {
            let color = selectedColor.usingColorSpace(.deviceRGB) ?? selectedColor
            defaults.set(color.redComponent, forKey: Keys.selectedColorRed)
            defaults.set(color.greenComponent, forKey: Keys.selectedColorGreen)
            defaults.set(color.blueComponent, forKey: Keys.selectedColorBlue)
            defaults.set(color.alphaComponent, forKey: Keys.selectedColorAlpha)
        }
    }

    var lineWidth: CGFloat = 3.0 {
        didSet { defaults.set(lineWidth, forKey: Keys.lineWidth) }
    }

    var fontSize: CGFloat = 32.0 {
        didSet { defaults.set(fontSize, forKey: Keys.fontSize) }
    }

    var useRoundedCorners: Bool = true {
        didSet { defaults.set(useRoundedCorners, forKey: Keys.useRoundedCorners) }
    }

    var mosaicType: MosaicType = .pixelateFine {
        didSet { defaults.set(mosaicType.rawValue, forKey: Keys.mosaicType) }
    }

    private init() {
        let appSupportPath = NSSearchPathForDirectoriesInDomains(.applicationSupportDirectory, .userDomainMask, true).first ?? "~/Library/Application Support"
        let defaultSavePath = (appSupportPath as NSString).appendingPathComponent("ShotShot/Screenshots")

        // Load existing settings (assign directly to avoid didSet until initial values are set)
        let storedSavePath = defaults.string(forKey: Keys.savePath) ?? defaultSavePath
        let storedModifiers = UInt32(defaults.integer(forKey: Keys.hotkeyModifiers))
        let storedKeyCode = UInt32(defaults.integer(forKey: Keys.hotkeyKeyCode))
        let storedClipboard = defaults.object(forKey: Keys.copyToClipboard) as? Bool ?? true
        let storedTimerSeconds = defaults.integer(forKey: Keys.timerSeconds)

        self.savePath = storedSavePath
        self.hotkeyModifiers = storedModifiers != 0 ? storedModifiers : UInt32(NSEvent.ModifierFlags.control.rawValue | NSEvent.ModifierFlags.shift.rawValue)
        self.hotkeyKeyCode = storedKeyCode != 0 ? storedKeyCode : 21  // "4" key
        self.copyToClipboard = storedClipboard
        self.timerSeconds = storedTimerSeconds > 0 ? storedTimerSeconds : 3

        // Load editor settings
        self.selectedToolName = defaults.string(forKey: Keys.selectedTool) ?? "select"

        // Load color (default: Skitch Pink)
        if defaults.object(forKey: Keys.selectedColorRed) != nil {
            let red = CGFloat(defaults.double(forKey: Keys.selectedColorRed))
            let green = CGFloat(defaults.double(forKey: Keys.selectedColorGreen))
            let blue = CGFloat(defaults.double(forKey: Keys.selectedColorBlue))
            let alpha = CGFloat(defaults.double(forKey: Keys.selectedColorAlpha))
            self.selectedColor = NSColor(red: red, green: green, blue: blue, alpha: alpha)
        } else {
            self.selectedColor = Self.defaultSkitchPink
        }

        // Load line width (default: 3.0)
        let storedLineWidth = defaults.double(forKey: Keys.lineWidth)
        self.lineWidth = storedLineWidth > 0 ? storedLineWidth : 3.0

        // Load font size (default: 32.0)
        let storedFontSize = defaults.double(forKey: Keys.fontSize)
        self.fontSize = storedFontSize > 0 ? storedFontSize : 32.0

        // Load rounded-corner setting (default: true)
        if defaults.object(forKey: Keys.useRoundedCorners) != nil {
            self.useRoundedCorners = defaults.bool(forKey: Keys.useRoundedCorners)
        } else {
            self.useRoundedCorners = true
        }

        // Load mosaic type (default: pixelateFine)
        if let storedMosaicType = defaults.string(forKey: Keys.mosaicType),
           let mosaicType = MosaicType(rawValue: storedMosaicType) {
            self.mosaicType = mosaicType
        } else {
            self.mosaicType = .pixelateFine
        }
    }
}
