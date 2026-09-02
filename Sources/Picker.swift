import AppKit
import MacAppKit

@MainActor
final class CommandPicker: PickerPanel<String> {
    static let shared = CommandPicker()
    private var capturedText: String?

    init() {
        super.init(title: "Commands", placeholder: "Search commands…",
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
        capturedText = nil
        let commands = CommandRunner.shared.listCommands()
        guard !commands.isEmpty else { return }
        show(items: commands)
    }

    func show() {
        guard !isVisible else { return }
        showFromMenu()
    }

    private func runPicked(_ command: String) {
        let precaptured = capturedText
        AppDelegate.previousApp?.activate()
        Task {
            let text: String
            if let precaptured, !precaptured.isEmpty {
                text = precaptured
            } else {
                try? await Task.sleep(nanoseconds: 200_000_000)
                // No selection is fine — run with empty input so output-only
                // commands (e.g. "Random Emoji") can still paste a result.
                let captured = await ContextCapture.captureSelected()
                text = (captured?.isEmpty == false) ? captured! : ""
            }
            await runCommand(command: command, text: text)
        }
    }

    /// Empty-results fallback: capture the selected text in the active app,
    /// prepend the typed query to it (separated by a blank line), and run the
    /// hidden `Custom` command with the combined string as `{{text}}`.
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
            guard let captured = await ContextCapture.captureSelected(), !captured.isEmpty else {
                NSSound.beep()
                return
            }
            let text = query + "\n\n" + captured
            await runCommand(command: "Custom", text: text)
        }
    }
}
