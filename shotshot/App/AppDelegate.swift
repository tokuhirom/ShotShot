import AppKit
import Carbon.HIToolbox
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private var menuBarManager: MenuBarManager?
    private var hotkeyManager: HotkeyManager?
    private var captureManager: CaptureManager?
    private var editorWindows: Set<NSWindow> = []
    private var keyEventMonitor: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupMenuBar()
        setupHotkey()
        setupCaptureManager()
        setupKeyEventMonitor()
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let monitor = keyEventMonitor {
            NSEvent.removeMonitor(monitor)
        }
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

    private func setupKeyEventMonitor() {
        // Cmd+V をローカルで監視（アプリがアクティブな時のみ）
        keyEventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            // Cmd+V (keyCode 9 = V)
            if event.modifierFlags.contains(.command) && event.keyCode == 9 {
                Task { @MainActor in
                    self?.pasteFromClipboard()
                }
                return nil  // イベントを消費
            }
            return event
        }
    }

    func pasteFromClipboard() {
        guard let image = ClipboardService.pasteImage() else {
            print("[shotshot] No image in clipboard")
            return
        }

        print("[shotshot] Pasted image from clipboard: \(image.size)")

        // Screenshot を作成（scaleFactor は 1.0、displayID は 0）
        let screenshot = Screenshot(
            image: image,
            displayID: 0,
            scaleFactor: 1.0
        )

        showEditor(with: screenshot)
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
        window.title = "ShotShot"
        window.contentView = NSHostingView(rootView: editorView)
        window.isReleasedWhenClosed = false  // ARC管理のため
        window.delegate = self  // ウィンドウ閉じた時に参照をクリア

        // 新しいウィンドウは少しずらして配置
        if let lastWindow = editorWindows.first {
            let lastFrame = lastWindow.frame
            window.setFrameOrigin(NSPoint(x: lastFrame.origin.x + 30, y: lastFrame.origin.y - 30))
        } else {
            window.center()
        }

        window.makeKeyAndOrderFront(nil)

        editorWindows.insert(window)
        NSApp.activate(ignoringOtherApps: true)
    }

    // NSWindowDelegate - ウィンドウが閉じられた時に参照をクリア
    nonisolated func windowWillClose(_ notification: Notification) {
        guard let closingWindow = notification.object as? NSWindow else { return }
        Task { @MainActor in
            self.editorWindows.remove(closingWindow)
        }
    }

    private func openSettings() {
        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func showPermissionAlert() {
        let alert = NSAlert()
        alert.messageText = "画面収録の許可が必要です"
        alert.informativeText = "システム設定 > プライバシーとセキュリティ > 画面収録 から ShotShot を許可してください。"
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
