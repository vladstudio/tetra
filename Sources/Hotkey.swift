import AppKit
import CoreGraphics

@MainActor
class HotkeyManager {
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private nonisolated(unsafe) var keyCode: UInt16 = 0
    private nonisolated(unsafe) var modifiers: CGEventFlags = []
    static var onHotkey: (() -> Void)?

    nonisolated init() {}

    /// Returns nil on success, or an error message on failure.
    @discardableResult
    func register(hotkey: String) -> String? {
        unregister()

        let parts = hotkey.lowercased().split(separator: "+").map { $0.trimmingCharacters(in: .whitespaces) }
        guard parts.count >= 2, let keyName = parts.last else {
            return "Invalid hotkey format: \(hotkey)"
        }

        guard let code = Self.keyCodes[keyName] else {
            return "Unknown key: \(keyName)"
        }

        var mods: CGEventFlags = []
        for mod in parts.dropLast() {
            switch mod {
            case "ctrl", "control": mods.insert(.maskControl)
            case "option", "alt": mods.insert(.maskAlternate)
            case "shift": mods.insert(.maskShift)
            case "cmd", "command": mods.insert(.maskCommand)
            default: return "Unknown modifier: \(mod)"
            }
        }

        keyCode = code
        modifiers = mods

        let userInfo = Unmanaged.passUnretained(self).toOpaque()
        let eventMask: CGEventMask = (1 << CGEventType.keyDown.rawValue)

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: eventMask,
            callback: hotkeyTapCallback,
            userInfo: userInfo
        ) else {
            return "Failed to create event tap (accessibility permission needed)"
        }

        eventTap = tap
        let source = CFMachPortCreateRunLoopSource(nil, tap, 0)
        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)

        print("[Tetra] Hotkey registered: \(hotkey)")
        return nil
    }

    func unregister() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
            runLoopSource = nil
        }
        eventTap = nil
    }

    fileprivate nonisolated func handleEvent(
        proxy: CGEventTapProxy, type: CGEventType, event: CGEvent
    ) -> Unmanaged<CGEvent>? {
        let pass = Unmanaged.passUnretained(event)

        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            DispatchQueue.main.async { MainActor.assumeIsolated { self.unregister() } }
            return pass
        }

        guard type == .keyDown else { return pass }

        let code = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
        let flags = event.flags.intersection([.maskControl, .maskAlternate, .maskShift, .maskCommand])

        guard code == keyCode, flags == modifiers else { return pass }

        DispatchQueue.main.async {
            MainActor.assumeIsolated {
                HotkeyManager.onHotkey?()
            }
        }
        return nil
    }

    // MARK: - Virtual key codes (US keyboard layout)

    private static let keyCodes: [String: UInt16] = [
        "a": 0x00, "s": 0x01, "d": 0x02, "f": 0x03, "h": 0x04, "g": 0x05,
        "z": 0x06, "x": 0x07, "c": 0x08, "v": 0x09, "b": 0x0B, "q": 0x0C,
        "w": 0x0D, "e": 0x0E, "r": 0x0F, "y": 0x10, "t": 0x11, "1": 0x12,
        "2": 0x13, "3": 0x14, "4": 0x15, "6": 0x16, "5": 0x17, "9": 0x19,
        "7": 0x1A, "8": 0x1C, "0": 0x1D, "o": 0x1F, "u": 0x20, "i": 0x22,
        "p": 0x23, "l": 0x25, "j": 0x26, "k": 0x28, "n": 0x2D, "m": 0x2E,
        "space": 0x31,
    ]
}

private func hotkeyTapCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    userInfo: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let userInfo else { return Unmanaged.passUnretained(event) }
    let manager = Unmanaged<HotkeyManager>.fromOpaque(userInfo).takeUnretainedValue()
    return manager.handleEvent(proxy: proxy, type: type, event: event)
}
