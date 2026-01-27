import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var menuBarManager: MenuBarManager?
    private var hotkeyManager: HotkeyManager?
    private var captureManager: CaptureManager?
    private var editorWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupMenuBar()
        setupHotkey()
        setupCaptureManager()
    }

    private func setupMenuBar() {
        menuBarManager = MenuBarManager(
            onCapture: { [weak self] in
                Task { @MainActor in
                    await self?.startCapture()
                }
            },
            onSettings: { [weak self] in
                self?.openSettings()
            },
            onQuit: {
                NSApplication.shared.terminate(nil)
            }
        )
    }

    private func setupHotkey() {
        hotkeyManager = HotkeyManager()
        hotkeyManager?.onHotkeyPressed = { [weak self] in
            Task { @MainActor in
                await self?.startCapture()
            }
        }
        hotkeyManager?.register()
    }

    private func setupCaptureManager() {
        captureManager = CaptureManager()
    }

    func startCapture() async {
        guard let captureManager = captureManager else {
            print("[shotshot] captureManager is nil")
            return
        }

        print("[shotshot] Starting capture...")
        do {
            let screenshot = try await captureManager.captureInteractively()
            print("[shotshot] Capture completed, showing editor...")
            showEditor(with: screenshot)
        } catch CaptureError.cancelled {
            print("[shotshot] Capture cancelled by user")
        } catch CaptureError.permissionDenied {
            print("[shotshot] Permission denied")
            showPermissionAlert()
        } catch {
            print("[shotshot] Capture error: \(error)")
            showErrorAlert(error: error)
        }
    }

    private func showEditor(with screenshot: Screenshot) {
        let viewModel = EditorViewModel(screenshot: screenshot)
        let editorView = EditorWindow(viewModel: viewModel)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "shotshot - Editor"
        window.contentView = NSHostingView(rootView: editorView)
        window.center()
        window.makeKeyAndOrderFront(nil)

        editorWindow = window
        NSApp.activate(ignoringOtherApps: true)
    }

    private func openSettings() {
        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func showPermissionAlert() {
        let alert = NSAlert()
        alert.messageText = "画面収録の許可が必要です"
        alert.informativeText = "システム設定 > プライバシーとセキュリティ > 画面収録 から shotshot を許可してください。"
        alert.alertStyle = .warning
        alert.addButton(withTitle: "システム設定を開く")
        alert.addButton(withTitle: "キャンセル")

        if alert.runModal() == .alertFirstButtonReturn {
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
                NSWorkspace.shared.open(url)
            }
        }
    }

    private func showErrorAlert(error: Error) {
        let alert = NSAlert()
        alert.messageText = "エラーが発生しました"
        alert.informativeText = error.localizedDescription
        alert.alertStyle = .critical
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}
