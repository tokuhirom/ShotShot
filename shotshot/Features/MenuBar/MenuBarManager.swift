import AppKit
import SwiftUI

@MainActor
final class MenuBarManager {
    private var statusItem: NSStatusItem?
    private let onCapture: () -> Void
    private let onSettings: () -> Void
    private let onQuit: () -> Void

    init(onCapture: @escaping () -> Void, onSettings: @escaping () -> Void, onQuit: @escaping () -> Void) {
        self.onCapture = onCapture
        self.onSettings = onSettings
        self.onQuit = onQuit
        setupStatusItem()
    }

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

        if let button = statusItem?.button {
            button.image = NSImage(systemSymbolName: "camera.viewfinder", accessibilityDescription: "shotshot")
            button.image?.isTemplate = true
        }

        let menu = NSMenu()

        let captureItem = NSMenuItem(title: "スクリーンショットを撮る", action: #selector(captureAction), keyEquivalent: "")
        captureItem.target = self
        captureItem.keyEquivalentModifierMask = [.control, .shift]
        captureItem.keyEquivalent = "4"
        menu.addItem(captureItem)

        menu.addItem(NSMenuItem.separator())

        let settingsItem = NSMenuItem(title: "設定...", action: #selector(settingsAction), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)

        menu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(title: "shotshot を終了", action: #selector(quitAction), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem?.menu = menu
    }

    @objc private func captureAction() {
        onCapture()
    }

    @objc private func settingsAction() {
        onSettings()
    }

    @objc private func quitAction() {
        onQuit()
    }
}
