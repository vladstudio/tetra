import AppKit
import Carbon.HIToolbox

class HotkeyManager {
    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?
    static var onHotkey: (() -> Void)?

    func register(hotkey: String) {
        unregister()

        let parts = hotkey.lowercased().split(separator: "+").map { $0.trimmingCharacters(in: .whitespaces) }
        guard parts.count >= 2, let keyName = parts.last else { return }

        guard let keyCode = Self.keyCodes[keyName] else {
            print("[tetra] Unknown key: \(keyName)")
            return
        }

        var modifiers: UInt32 = 0
        for mod in parts.dropLast() {
            switch mod {
            case "ctrl", "control": modifiers |= UInt32(controlKey)
            case "option", "alt": modifiers |= UInt32(optionKey)
            case "shift": modifiers |= UInt32(shiftKey)
            case "cmd", "command": modifiers |= UInt32(cmdKey)
            default: break
            }
        }

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed))

        InstallEventHandler(
            GetApplicationEventTarget(),
            { (_, _, _) -> OSStatus in
                HotkeyManager.onHotkey?()
                return noErr
            },
            1, &eventType, nil, &handlerRef)

        let hotKeyID = EventHotKeyID(signature: 0x54_45_54_52, id: 1) // "TETR"
        RegisterEventHotKey(keyCode, modifiers, hotKeyID, GetApplicationEventTarget(), 0, &hotKeyRef)
        print("[tetra] Hotkey registered: \(hotkey)")
    }

    func unregister() {
        if let ref = hotKeyRef {
            UnregisterEventHotKey(ref)
            hotKeyRef = nil
        }
        if let ref = handlerRef {
            RemoveEventHandler(ref)
            handlerRef = nil
        }
    }

    // MARK: - Clipboard capture (simulates Cmd+C)

    static func captureSelectedText() -> String? {
        let pasteboard = NSPasteboard.general
        let oldCount = pasteboard.changeCount

        simulateKeyCombo(keyCode: 0x08, flags: .maskCommand) // Cmd+C
        Thread.sleep(forTimeInterval: 0.1)

        guard pasteboard.changeCount != oldCount else { return nil }
        return pasteboard.string(forType: .string)
    }

    // MARK: - Paste back (simulates Cmd+V)

    static func pasteText(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        simulateKeyCombo(keyCode: 0x09, flags: .maskCommand) // Cmd+V
    }

    // MARK: - Key simulation

    private static func simulateKeyCombo(keyCode: CGKeyCode, flags: CGEventFlags) {
        let source = CGEventSource(stateID: .hidSystemState)
        let down = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true)
        let up = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false)
        down?.flags = flags
        up?.flags = flags
        down?.post(tap: .cghidEventTap)
        up?.post(tap: .cghidEventTap)
    }

    // MARK: - Virtual key codes (US keyboard layout)

    private static let keyCodes: [String: UInt32] = [
        "a": 0x00, "s": 0x01, "d": 0x02, "f": 0x03, "h": 0x04, "g": 0x05,
        "z": 0x06, "x": 0x07, "c": 0x08, "v": 0x09, "b": 0x0B, "q": 0x0C,
        "w": 0x0D, "e": 0x0E, "r": 0x0F, "y": 0x10, "t": 0x11, "1": 0x12,
        "2": 0x13, "3": 0x14, "4": 0x15, "6": 0x16, "5": 0x17, "9": 0x19,
        "7": 0x1A, "8": 0x1C, "0": 0x1D, "o": 0x1F, "u": 0x20, "i": 0x22,
        "p": 0x23, "l": 0x25, "j": 0x26, "k": 0x28, "n": 0x2D, "m": 0x2E,
        "space": 0x31,
    ]
}
