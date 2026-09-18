import AppKit
import MacAppKit

@MainActor
final class CommandPicker: PickerPanel<String> {
    static let shared = CommandPicker()

    private enum InputSource { case selection, clipboard, empty }

    init() {
        super.init(title: "Transform", placeholder: "Search commands…",
                   searchKey: "CommandPicker.lastSearch",
                   appearance: NSAppearance(named: .darkAqua))
        setFilter { query, commands in
            let q = query.lowercased()
            return commands.compactMap { c -> (String, Int)? in
                Fuzzy.score(query: q, target: c.lowercased()).map { (c, $0) }
            }
            .sorted { $0.1 > $1.1 }.map { $0.0 }
        }
        onPick { [weak self] _, command in
            self?.runPicked(command)
        }
        onEmptyPick { [weak self] query in
            self?.runCustom(query)
        }
    }

    required init?(coder: NSCoder) { fatalError() }

    func showFromMenu() {
        guard Permissions.isGranted(.accessibility) else {
            Permissions.openSettings(.accessibility)
            return
        }
        let commands = CommandRunner.shared.listCommands()
        guard !commands.isEmpty else { return }

        switch Self.detectInputSource() {
        case .selection:
            title = "Transform selected text"
            setHint(nil)
        case .clipboard:
            title = "Transform and paste"
            setHint(nil)
        case .empty:
            title = "Transform"
            setHint("Select some text or copy text to clipboard to transform it with Tetra.")
        }
        show(items: commands)
    }

    func show() {
        guard !isVisible else { return }
        showFromMenu()
    }

    // MARK: - Input detection (at open time, for the title/hint)

    private static func detectInputSource() -> InputSource {
        if let app = AppDelegate.previousApp, hasAXSelection(in: app) {
            return .selection
        }
        // Fallback disabled: selection-only mode — the old behavior.
        guard ConfigManager.shared.config.clipboardFallback else { return .selection }
        return clipboardText() != nil ? .clipboard : .empty
    }

    /// AX check for non-empty selected text on the focused element of `app`.
    /// Works on background apps — no keystrokes, no focus changes. Apps that
    /// don't expose the attribute are indistinguishable from "no selection"
    /// here; the Cmd+C probe at pick time still finds their selection.
    private static func hasAXSelection(in app: NSRunningApplication) -> Bool {
        let axApp = AXUIElementCreateApplication(app.processIdentifier)
        var focusedRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(axApp, kAXFocusedUIElementAttribute as CFString, &focusedRef) == .success else { return false }
        let el = focusedRef as! AXUIElement
        var selRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(el, kAXSelectedTextAttribute as CFString, &selRef) == .success,
              let text = selRef as? String,
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        return true
    }

    /// The clipboard's text, or nil if it holds none (or only whitespace).
    private static func clipboardText() -> String? {
        guard let text = NSPasteboard.general.string(forType: .string) else { return nil }
        return text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : text
    }

    // MARK: - Running

    private func runPicked(_ command: String) {
        AppDelegate.previousApp?.activate()
        Task {
            try? await Task.sleep(nanoseconds: 200_000_000)
            // Capture order: selection, then clipboard (if enabled), then empty
            // input so output-only commands (e.g. "Random Emoji") still work.
            var text = await ContextCapture.captureSelected() ?? ""
            if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
               ConfigManager.shared.config.clipboardFallback {
                text = Self.clipboardText() ?? ""
            }
            await runCommand(command: command, text: text)
        }
    }

    /// Empty-results fallback: capture the selected text in the active app,
    /// prepend the typed query to it (separated by a blank line), and run the
    /// hidden `Custom` command with the combined string as `{{text}}`.
    /// Falls back to the clipboard when nothing is selected.
    /// Fails loudly if `Custom.prompt.md` does not exist.
    private func runCustom(_ query: String) {
        guard !query.isEmpty else { return }
        let file = CommandRunner.shared.commandsDir
            .appendingPathComponent(CommandRunner.customFileName)
        guard FileManager.default.fileExists(atPath: file.path) else {
            NSSound.beep()
            AppStatus.shared.lastError = "Custom command not found: \(file.path)"
            return
        }
        AppDelegate.previousApp?.activate()
        Task {
            try? await Task.sleep(nanoseconds: 200_000_000)
            var captured = await ContextCapture.captureSelected() ?? ""
            if captured.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
               ConfigManager.shared.config.clipboardFallback {
                captured = Self.clipboardText() ?? ""
            }
            guard !captured.isEmpty else {
                NSSound.beep()
                return
            }
            let text = query + "\n\n" + captured
            await runCommand(command: "Custom", text: text)
        }
    }
}
