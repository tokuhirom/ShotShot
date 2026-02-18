import AppKit
import Carbon.HIToolbox
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private var menuBarManager: MenuBarManager?
    private var hotkeyManager: HotkeyManager?
    private var captureManager: CaptureManager?
    private var recordingManager: RecordingManager?
    private var scrollCaptureManager: ScrollCaptureManager?
    private var editorWindows: Set<NSWindow> = []
    private var settingsWindow: NSWindow?
    private var keyEventMonitor: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupMenuBar()
        setupHotkey()
        setupCaptureManager()
        setupRecordingManager()
        setupScrollCaptureManager()
        setupKeyEventMonitor()
        setupHotkeyChangeObserver()
        setupTimerSettingsObserver()
    }

    private func setupHotkeyChangeObserver() {
        NotificationCenter.default.addObserver(
            forName: .hotkeySettingsChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.hotkeyManager?.reregister()
            }
        }
    }

    private func setupTimerSettingsObserver() {
        NotificationCenter.default.addObserver(
            forName: .timerSettingsChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                let seconds = AppSettings.shared.timerSeconds
                self?.menuBarManager?.updateTimerSeconds(seconds)
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let monitor = keyEventMonitor {
            NSEvent.removeMonitor(monitor)
        }
        recordingManager?.stopRecording()
    }

    private func setupMenuBar() {
        menuBarManager = MenuBarManager(
            onCapture: { [weak self] in
                Task { @MainActor in
                    await self?.startCapture()
                }
            },
            onTimerCapture: { [weak self] in
                Task { @MainActor in
                    await self?.startTimerCapture()
                }
            },
            onScrollCapture: { [weak self] in
                Task { @MainActor in
                    await self?.startScrollCapture()
                }
            },
            onRecording: { [weak self] in
                Task { @MainActor in
                    await self?.startRecording()
                }
            },
            onStopRecording: { [weak self] in
                self?.recordingManager?.stopRecording()
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

    private func setupRecordingManager() {
        recordingManager = RecordingManager()
    }

    private func setupScrollCaptureManager() {
        scrollCaptureManager = ScrollCaptureManager()
    }

    private func setupKeyEventMonitor() {
        // Monitor Cmd+V locally (only when the app is active)
        keyEventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            // Cmd+V (keyCode 9 = V)
            if event.modifierFlags.contains(.command) && event.keyCode == 9 {
                Task { @MainActor in
                    self?.pasteFromClipboard()
                }
                return nil  // Consume the event
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

        // Create a Screenshot (scaleFactor is 1.0, displayID is 0)
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
            let filename = saveInitialScreenshot(screenshot)
            showEditor(with: screenshot, initialFilename: filename)
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

    func startTimerCapture() async {
        guard let captureManager = captureManager else {
            print("[shotshot] captureManager is nil")
            return
        }

        let countdownSeconds = AppSettings.shared.timerSeconds
        print("[shotshot] Starting timer capture...")
        do {
            let screenshot = try await captureManager.captureWithTimer(countdownSeconds: countdownSeconds)
            print("[shotshot] Timer capture completed, showing editor...")
            let filename = saveInitialScreenshot(screenshot)
            showEditor(with: screenshot, initialFilename: filename)
        } catch CaptureError.cancelled {
            print("[shotshot] Timer capture cancelled by user")
        } catch CaptureError.permissionDenied {
            print("[shotshot] Permission denied")
            showPermissionAlert()
        } catch {
            print("[shotshot] Timer capture error: \(error)")
            showErrorAlert(error: error)
        }
    }

    func startRecording() async {
        guard let captureManager = captureManager, let recordingManager = recordingManager else {
            print("[shotshot] captureManager or recordingManager is nil")
            return
        }

        // Stop if already recording
        if recordingManager.isRecording {
            recordingManager.stopRecording()
            return
        }

        print("[shotshot] Starting recording...")
        menuBarManager?.updateRecordingState(isRecording: true)

        do {
            let selection = try await captureManager.selectArea()
            let tempURL = try await recordingManager.startRecording(selection: selection)
            menuBarManager?.updateRecordingState(isRecording: false)
            print("[shotshot] Recording stopped, showing save panel...")
            await VideoExporter.showSavePanel(tempMP4URL: tempURL)
        } catch CaptureError.cancelled {
            print("[shotshot] Recording cancelled by user")
            menuBarManager?.updateRecordingState(isRecording: false)
        } catch CaptureError.permissionDenied {
            print("[shotshot] Permission denied")
            menuBarManager?.updateRecordingState(isRecording: false)
            showPermissionAlert()
        } catch {
            print("[shotshot] Recording error: \(error)")
            menuBarManager?.updateRecordingState(isRecording: false)
            showErrorAlert(error: error)
        }
    }

    func startScrollCapture() async {
        guard let scrollCaptureManager = scrollCaptureManager else {
            print("[shotshot] scrollCaptureManager is nil")
            return
        }

        print("[shotshot] Starting scroll capture...")
        do {
            let screenshot = try await scrollCaptureManager.startScrollCapture()
            print("[shotshot] Scroll capture completed, showing editor...")
            let filename = saveInitialScreenshot(screenshot)
            showEditor(with: screenshot, initialFilename: filename)
        } catch CaptureError.cancelled {
            print("[shotshot] Scroll capture cancelled by user")
        } catch CaptureError.permissionDenied {
            print("[shotshot] Permission denied")
            showPermissionAlert()
        } catch {
            print("[shotshot] Scroll capture error: \(error)")
            showErrorAlert(error: error)
        }
    }

    /// Saves the raw screenshot to file and clipboard immediately after capture.
    /// Returns the generated filename (without extension) for later use when overwriting.
    @discardableResult
    private func saveInitialScreenshot(_ screenshot: Screenshot) -> String? {
        let settings = AppSettings.shared
        let filename = ImageExporter.generateFilename()
        do {
            let url = try ImageExporter.save(screenshot, to: settings.savePath, filename: filename)
            print("[shotshot] Initial save to: \(url.path)")
        } catch {
            print("[shotshot] Initial save failed: \(error)")
            return nil
        }
        ClipboardService.copy(screenshot.image)
        return filename
    }

    private func showEditor(with screenshot: Screenshot, initialFilename: String? = nil) {
        let viewModel = EditorViewModel(screenshot: screenshot, initialFilename: initialFilename)
        let editorView = EditorWindow(viewModel: viewModel)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "ShotShot"
        window.contentView = NSHostingView(rootView: editorView)
        window.isReleasedWhenClosed = false  // Keep under ARC management
        window.delegate = self  // Clear reference when the window closes

        // Stagger new windows slightly
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

    // NSWindowDelegate - Clear reference when the window closes
    nonisolated func windowWillClose(_ notification: Notification) {
        guard let closingWindow = notification.object as? NSWindow else { return }
        Task { @MainActor in
            self.editorWindows.remove(closingWindow)
        }
    }

    private func openSettings() {
        print("[shotshot] openSettings called")

        // Bring existing window to front if it exists
        if let window = settingsWindow, window.isVisible {
            print("[shotshot] Existing settings window found, bringing to front")
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        print("[shotshot] Creating new settings window")
        let settingsView = SettingsView()
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 350),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = NSLocalizedString("app.settings_title", comment: "")
        window.contentView = NSHostingView(rootView: settingsView)
        window.center()
        window.isReleasedWhenClosed = false
        window.makeKeyAndOrderFront(nil)

        settingsWindow = window
        NSApp.activate(ignoringOtherApps: true)
        print("[shotshot] Settings window created and shown")
    }

    private func showPermissionAlert() {
        let alert = NSAlert()
        alert.messageText = NSLocalizedString("permission.screen_recording.title", comment: "")
        alert.informativeText = NSLocalizedString("permission.screen_recording.message", comment: "")
        alert.alertStyle = .warning
        alert.addButton(withTitle: NSLocalizedString("permission.open_system_settings", comment: ""))
        alert.addButton(withTitle: NSLocalizedString("common.cancel", comment: ""))

        if alert.runModal() == .alertFirstButtonReturn {
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
                NSWorkspace.shared.open(url)
            }
        }
    }

    private func showErrorAlert(error: Error) {
        let alert = NSAlert()
        alert.messageText = NSLocalizedString("error.generic.title", comment: "")
        alert.informativeText = error.localizedDescription
        alert.alertStyle = .critical
        alert.addButton(withTitle: NSLocalizedString("common.ok", comment: ""))
        alert.runModal()
    }
}
