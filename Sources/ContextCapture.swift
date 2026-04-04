import AppKit

enum ContextCapture {
    /// Capture selected text from the active app.
    /// Tries Accessibility API first (native apps), falls back to Cmd+C (Electron/web apps).
    static func captureSelected() async -> String? {
        if let text = selectedViaAX() { return text }
        return await selectedViaClipboard()
    }

    // MARK: - Accessibility API (preferred)

    private static func selectedViaAX() -> String? {
        guard let app = NSWorkspace.shared.frontmostApplication,
              app.bundleIdentifier != Bundle.main.bundleIdentifier else { return nil }
        let axApp = AXUIElementCreateApplication(app.processIdentifier)
        guard let el: AXUIElement = axAttr(axApp, kAXFocusedUIElementAttribute) else { return nil }
        let text: String? = axAttr(el, kAXSelectedTextAttribute)
        guard let text, !text.isEmpty else { return nil }
        return text
    }

    // MARK: - Clipboard fallback (Electron/web apps)

    private static func selectedViaClipboard() async -> String? {
        let pb = NSPasteboard.general
        let savedCount = pb.changeCount
        let savedItems = pb.pasteboardItems?.map { item in
            item.types.compactMap { type in
                item.data(forType: type).map { (type, $0) }
            }
        } ?? []

        // Simulate Cmd+C
        let src = CGEventSource(stateID: .hidSystemState)
        guard let down = CGEvent(keyboardEventSource: src, virtualKey: 0x08, keyDown: true),
              let up = CGEvent(keyboardEventSource: src, virtualKey: 0x08, keyDown: false) else { return nil }
        down.flags = .maskCommand
        up.flags = .maskCommand
        down.post(tap: .cgAnnotatedSessionEventTap)
        up.post(tap: .cgAnnotatedSessionEventTap)

        try? await Task.sleep(nanoseconds: 100_000_000)

        // Check if clipboard changed
        guard pb.changeCount != savedCount,
              let text = pb.string(forType: .string), !text.isEmpty else {
            return nil
        }

        // Restore original clipboard
        if !savedItems.isEmpty {
            pb.clearContents()
            for itemData in savedItems {
                let item = NSPasteboardItem()
                for (type, data) in itemData { item.setData(data, forType: type) }
                pb.writeObjects([item])
            }
        }

        return text
    }

    // MARK: - AX helpers

    private static func axAttr<T>(_ el: AXUIElement, _ attr: String) -> T? {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(el, attr as CFString, &ref) == .success else { return nil }
        return ref as? T
    }
}
