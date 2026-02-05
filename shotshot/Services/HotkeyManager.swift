import AppKit
import Carbon
import Foundation

@MainActor
final class HotkeyManager {
    private var eventHandler: EventHandlerRef?
    private var hotkeyRef: EventHotKeyRef?
    private var scrollCaptureHotkeyRef: EventHotKeyRef?
    private static var sharedInstance: HotkeyManager?

    var onHotkeyPressed: (() -> Void)?
    var onScrollCaptureHotkeyPressed: (() -> Void)?

    init() {
        HotkeyManager.sharedInstance = self
    }

    func register() {
        let settings = AppSettings.shared

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        let handlerCallback: EventHandlerUPP = { _, event, _ in
            var hotkeyID = EventHotKeyID()
            GetEventParameter(
                event,
                EventParamName(kEventParamDirectObject),
                EventParamType(typeEventHotKeyID),
                nil,
                MemoryLayout<EventHotKeyID>.size,
                nil,
                &hotkeyID
            )

            Task { @MainActor in
                if hotkeyID.id == 1 {
                    HotkeyManager.sharedInstance?.onHotkeyPressed?()
                } else if hotkeyID.id == 2 {
                    HotkeyManager.sharedInstance?.onScrollCaptureHotkeyPressed?()
                }
            }
            return noErr
        }

        InstallEventHandler(
            GetApplicationEventTarget(),
            handlerCallback,
            1,
            &eventType,
            nil,
            &eventHandler
        )

        // Register main capture hotkey (Ctrl+Shift+4)
        let hotkeyID = EventHotKeyID(signature: OSType(0x5353_4854), id: 1) // "SSHT"
        let modifiers = carbonModifiers(from: settings.hotkeyModifiers)

        RegisterEventHotKey(
            settings.hotkeyKeyCode,
            modifiers,
            hotkeyID,
            GetApplicationEventTarget(),
            0,
            &hotkeyRef
        )

        // Register scroll capture hotkey (Ctrl+Shift+7)
        let scrollCaptureHotkeyID = EventHotKeyID(signature: OSType(0x5353_4854), id: 2) // "SSHT" with id 2
        let scrollCaptureModifiers = UInt32(controlKey) | UInt32(shiftKey)
        let scrollCaptureKeyCode: UInt32 = 0x1A  // Key code for '7'

        RegisterEventHotKey(
            scrollCaptureKeyCode,
            scrollCaptureModifiers,
            scrollCaptureHotkeyID,
            GetApplicationEventTarget(),
            0,
            &scrollCaptureHotkeyRef
        )
    }

    func unregister() {
        if let hotkeyRef = hotkeyRef {
            UnregisterEventHotKey(hotkeyRef)
            self.hotkeyRef = nil
        }
        if let scrollCaptureHotkeyRef = scrollCaptureHotkeyRef {
            UnregisterEventHotKey(scrollCaptureHotkeyRef)
            self.scrollCaptureHotkeyRef = nil
        }
        if let eventHandler = eventHandler {
            RemoveEventHandler(eventHandler)
            self.eventHandler = nil
        }
    }

    func reregister() {
        unregister()
        register()
    }

    private func carbonModifiers(from cocoaModifiers: UInt32) -> UInt32 {
        var result: UInt32 = 0

        if cocoaModifiers & UInt32(NSEvent.ModifierFlags.control.rawValue) != 0 {
            result |= UInt32(controlKey)
        }
        if cocoaModifiers & UInt32(NSEvent.ModifierFlags.shift.rawValue) != 0 {
            result |= UInt32(shiftKey)
        }
        if cocoaModifiers & UInt32(NSEvent.ModifierFlags.option.rawValue) != 0 {
            result |= UInt32(optionKey)
        }
        if cocoaModifiers & UInt32(NSEvent.ModifierFlags.command.rawValue) != 0 {
            result |= UInt32(cmdKey)
        }

        return result
    }
}
