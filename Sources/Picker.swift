import AppKit
import MacAppKit

@MainActor
final class CommandPicker: PickerPanel<String> {
    static let shared = CommandPicker()

    private enum InputSource { case selection, clipboard, empty }
    /// Decided when the picker opens and honored at pick time: the clipboard
    /// is never used as input when a selection was seen.
    private var inputSource: InputSource = .empty

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
            self?.run(command: command, prefix: nil)
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

        inputSource = Self.detectInputSource()
        switch inputSource {
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

    /// Runs `command` on the captured input. Priority is strict: selected text
    /// first; the clipboard is only consulted when the capture finds no
    /// selection — and never when the picker saw one at open time, even if the
    /// recapture then fails. `prefix` (the Custom command) prepends the typed
    /// query to the captured text.
    private func run(command: String, prefix: String?) {
        AppDelegate.previousApp?.activate()
        Task {
            await Self.waitUntilFrontmost()
            var text = await ContextCapture.captureSelected() ?? ""
            if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
               inputSource != .selection,
               ConfigManager.shared.config.clipboardFallback {
                text = Self.clipboardText() ?? ""
            }
            if let prefix {
                guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    NSSound.beep()
                    return
                }
                text = prefix + "\n\n" + text
            } else if text.isEmpty, inputSource == .selection {
                NSSound.beep() // saw a selection at open but couldn't recapture it
            }
            await runCommand(command: command, text: text)
        }
    }

    /// Custom fallback: the typed query acts as an inline instruction and the
    /// selection is the payload, fed to the hidden `Custom.prompt.md`.
    private func runCustom(_ query: String) {
        guard !query.isEmpty else { return }
        let file = CommandRunner.shared.commandsDir
            .appendingPathComponent(CommandRunner.customFileName)
        guard FileManager.default.fileExists(atPath: file.path) else {
            NSSound.beep()
            AppStatus.shared.lastError = "Custom command not found: \(file.path)"
            return
        }
        run(command: "Custom", prefix: query)
    }

    /// `activate()` is async and cooperative — capturing too early misses the
    /// AX selection and fires the Cmd+C probe into the void, which let the old
    /// clipboard win over a real selection. Poll until the target app is
    /// frontmost, bounded so a failed activation costs half a second at most.
    private static func waitUntilFrontmost() async {
        guard let app = AppDelegate.previousApp else { return }
        let deadline = Date().addingTimeInterval(0.5)
        while Date() < deadline,
              NSWorkspace.shared.frontmostApplication?.processIdentifier != app.processIdentifier {
            try? await Task.sleep(nanoseconds: 25_000_000)
        }
    }
}
