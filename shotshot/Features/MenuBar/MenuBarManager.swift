import AppKit
import SwiftUI

@MainActor
final class MenuBarManager {
    private var statusItem: NSStatusItem?
    private let onCapture: () -> Void
    private let onTimerCapture: () -> Void
    private let onScrollCapture: () -> Void
    private let onRecording: () -> Void
    private let onStopRecording: () -> Void
    private let onSettings: () -> Void
    private let onQuit: () -> Void
    private var recordMenuItem: NSMenuItem?
    private var timerMenuItem: NSMenuItem?
    private var isRecordingActive: Bool = false

    init(
        onCapture: @escaping () -> Void,
        onTimerCapture: @escaping () -> Void,
        onScrollCapture: @escaping () -> Void,
        onRecording: @escaping () -> Void,
        onStopRecording: @escaping () -> Void,
        onSettings: @escaping () -> Void,
        onQuit: @escaping () -> Void
    ) {
        self.onCapture = onCapture
        self.onTimerCapture = onTimerCapture
        self.onScrollCapture = onScrollCapture
        self.onRecording = onRecording
        self.onStopRecording = onStopRecording
        self.onSettings = onSettings
        self.onQuit = onQuit
        setupStatusItem()
    }

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

        if let button = statusItem?.button {
            button.image = NSImage(
                systemSymbolName: "camera.viewfinder",
                accessibilityDescription: NSLocalizedString("app.name", comment: "")
            )
            button.image?.isTemplate = true
        }

        let menu = NSMenu()

        let captureItem = NSMenuItem(title: NSLocalizedString("menu.capture", comment: ""), action: #selector(captureAction), keyEquivalent: "")
        captureItem.target = self
        captureItem.keyEquivalentModifierMask = [.control, .shift]
        captureItem.keyEquivalent = "4"
        menu.addItem(captureItem)

        let timerSeconds = AppSettings.shared.timerSeconds
        let timerTitle = String.localizedStringWithFormat(
            NSLocalizedString("menu.timer_capture_format", comment: ""),
            timerSeconds
        )
        let timerCaptureItem = NSMenuItem(title: timerTitle, action: #selector(timerCaptureAction), keyEquivalent: "")
        timerCaptureItem.target = self
        timerCaptureItem.keyEquivalentModifierMask = [.control, .shift]
        timerCaptureItem.keyEquivalent = "5"
        menu.addItem(timerCaptureItem)
        self.timerMenuItem = timerCaptureItem

        let scrollCaptureItem = NSMenuItem(title: NSLocalizedString("menu.scroll_capture", comment: ""), action: #selector(scrollCaptureAction), keyEquivalent: "")
        scrollCaptureItem.target = self
        scrollCaptureItem.keyEquivalentModifierMask = [.control, .shift]
        scrollCaptureItem.keyEquivalent = "7"
        menu.addItem(scrollCaptureItem)

        let recordItem = NSMenuItem(title: NSLocalizedString("menu.record_start", comment: ""), action: #selector(recordAction), keyEquivalent: "")
        recordItem.target = self
        recordItem.keyEquivalentModifierMask = [.control, .shift]
        recordItem.keyEquivalent = "6"
        menu.addItem(recordItem)
        self.recordMenuItem = recordItem

        menu.addItem(NSMenuItem.separator())

        let openFolderItem = NSMenuItem(title: NSLocalizedString("menu.open_save_folder", comment: ""), action: #selector(openSaveFolderAction), keyEquivalent: "")
        openFolderItem.target = self
        menu.addItem(openFolderItem)

        menu.addItem(NSMenuItem.separator())

        let settingsItem = NSMenuItem(title: NSLocalizedString("menu.settings", comment: ""), action: #selector(settingsAction), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)

        menu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(title: NSLocalizedString("menu.quit", comment: ""), action: #selector(quitAction), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem?.menu = menu
    }

    @objc private func captureAction() {
        onCapture()
    }

    @objc private func timerCaptureAction() {
        onTimerCapture()
    }

    @objc private func scrollCaptureAction() {
        onScrollCapture()
    }

    @objc private func recordAction() {
        if isRecordingActive {
            onStopRecording()
        } else {
            onRecording()
        }
    }

    func updateRecordingState(isRecording: Bool) {
        isRecordingActive = isRecording
        if isRecording {
            recordMenuItem?.title = NSLocalizedString("menu.record_stop", comment: "")
        } else {
            recordMenuItem?.title = NSLocalizedString("menu.record_start", comment: "")
        }
    }

    func updateTimerSeconds(_ seconds: Int) {
        let title = String.localizedStringWithFormat(
            NSLocalizedString("menu.timer_capture_format", comment: ""),
            seconds
        )
        timerMenuItem?.title = title
    }

    @objc private func openSaveFolderAction() {
        let savePath = AppSettings.shared.savePath
        let url = URL(fileURLWithPath: savePath)

        // Create directory if it doesn't exist
        let fileManager = FileManager.default
        if !fileManager.fileExists(atPath: savePath) {
            try? fileManager.createDirectory(at: url, withIntermediateDirectories: true)
        }

        NSWorkspace.shared.open(url)
    }

    @objc private func settingsAction() {
        onSettings()
    }

    @objc private func quitAction() {
        onQuit()
    }
}
