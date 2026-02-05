import AppKit
import Carbon
import Foundation

@MainActor
final class HotkeyManager {
    private var eventHandler: EventHandlerRef?
    private var hotkeyRef: EventHotKeyRef?
    private static var sharedInstance: HotkeyManager?

    var onHotkeyPressed: (() -> Void)?

    init() {
        HotkeyManager.sharedInstance = self
    }

    func register() {
        let settings = AppSettings.shared

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        let handlerCallback: EventHandlerUPP = { _, _, _ in
            Task { @MainActor in
                HotkeyManager.sharedInstance?.onHotkeyPressed?()
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
    }

    func unregister() {
        if let hotkeyRef = hotkeyRef {
            UnregisterEventHotKey(hotkeyRef)
            self.hotkeyRef = nil
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
