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
        onPick { [weak self] _, command in
            self?.runPicked(command)
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
                guard let captured = await ContextCapture.captureSelected(), !captured.isEmpty else {
                    NSSound.beep()
                    return
                }
                text = captured
            }
            await runCommand(command: command, text: text)
        }
    }
}
