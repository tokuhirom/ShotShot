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
            button.image = NSImage(systemSymbolName: "camera.viewfinder", accessibilityDescription: "ShotShot")
            button.image?.isTemplate = true
        }

        let menu = NSMenu()

        let captureItem = NSMenuItem(title: "スクリーンショットを撮る", action: #selector(captureAction), keyEquivalent: "")
        captureItem.target = self
        captureItem.keyEquivalentModifierMask = [.control, .shift]
        captureItem.keyEquivalent = "4"
        menu.addItem(captureItem)

        let timerSeconds = AppSettings.shared.timerSeconds
        let timerCaptureItem = NSMenuItem(title: "タイマーで撮る (\(timerSeconds)秒)", action: #selector(timerCaptureAction), keyEquivalent: "")
        timerCaptureItem.target = self
        timerCaptureItem.keyEquivalentModifierMask = [.control, .shift]
        timerCaptureItem.keyEquivalent = "5"
        menu.addItem(timerCaptureItem)
        self.timerMenuItem = timerCaptureItem

        let scrollCaptureItem = NSMenuItem(title: "スクロールキャプチャ", action: #selector(scrollCaptureAction), keyEquivalent: "")
        scrollCaptureItem.target = self
        scrollCaptureItem.keyEquivalentModifierMask = [.control, .shift]
        scrollCaptureItem.keyEquivalent = "7"
        menu.addItem(scrollCaptureItem)

        let recordItem = NSMenuItem(title: "画面を録画する", action: #selector(recordAction), keyEquivalent: "")
        recordItem.target = self
        recordItem.keyEquivalentModifierMask = [.control, .shift]
        recordItem.keyEquivalent = "6"
        menu.addItem(recordItem)
        self.recordMenuItem = recordItem

        menu.addItem(NSMenuItem.separator())

        let openFolderItem = NSMenuItem(title: "保存先を開く", action: #selector(openSaveFolderAction), keyEquivalent: "")
        openFolderItem.target = self
        menu.addItem(openFolderItem)

        menu.addItem(NSMenuItem.separator())

        let settingsItem = NSMenuItem(title: "設定...", action: #selector(settingsAction), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)

        menu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(title: "ShotShot を終了", action: #selector(quitAction), keyEquivalent: "q")
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
        if recordMenuItem?.title == "録画を停止する" {
            onStopRecording()
        } else {
            onRecording()
        }
    }

    func updateRecordingState(isRecording: Bool) {
        if isRecording {
            recordMenuItem?.title = "録画を停止する"
        } else {
            recordMenuItem?.title = "画面を録画する"
        }
    }

    func updateTimerSeconds(_ seconds: Int) {
        timerMenuItem?.title = "タイマーで撮る (\(seconds)秒)"
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
