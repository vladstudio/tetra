import MacAppKit
import SwiftUI

@Observable
@MainActor
final class CommandState {
    static let shared = CommandState()
    var isRunning = false
    var runningCommand: String?
    var runningProcess: Process?
    var runningTask: Task<Void, Never>?
    func cancel() {
        runningProcess?.terminate()
        runningTask?.cancel()
    }
}

@Observable
@MainActor
final class AppStatus {
    static let shared = AppStatus()
    var configError: String?
    var serverError: String?
    var hotkeyError: String?
    var lastError: String?
    var port: Int = 24100
    var hotkey: String = "ctrl+option+t"
}

@main
struct TetraApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    private let commandState = CommandState.shared
    private let appStatus = AppStatus.shared

    private static let menuBarIcon = loadIcon("MenuBarIcon")
    private static let thinkIcon = loadIcon("ThinkIcon")
    private static let warningIcon = loadIcon("WarningIcon")

    private static func loadIcon(_ name: String) -> NSImage {
        if let url = Bundle.module.url(forResource: name, withExtension: "png"),
           let img = NSImage(contentsOf: url)
        {
            img.size = NSSize(width: 18, height: 18)
            img.isTemplate = true
            return img
        }
        return NSImage(systemSymbolName: "text.cursor", accessibilityDescription: "Tetra")!
    }

    private var hasError: Bool {
        appStatus.configError != nil
            || appStatus.serverError != nil
            || appStatus.hotkeyError != nil
    }

    var body: some Scene {
        MenuBarExtra {
            MenuBarView()
        } label: {
            Image(nsImage: commandState.isRunning ? Self.thinkIcon
                : hasError ? Self.warningIcon
                : Self.menuBarIcon)
        }
    }
}

// MARK: - AppDelegate

class AppDelegate: NSObject, NSApplicationDelegate {
    @MainActor static var previousApp: NSRunningApplication?
    private var server = TetraServer()
    private var hotkeyManager = HotkeyManager()
    private var activePort: UInt16 = 0

    func applicationDidFinishLaunching(_ notification: Notification) {
        let config = ConfigManager.shared.config

        // Track the last non-Tetra frontmost app (seed with current)
        if let front = NSWorkspace.shared.frontmostApplication,
           front.bundleIdentifier != Bundle.main.bundleIdentifier {
            AppDelegate.previousApp = front
        }
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil, queue: .main) { notification in
            guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  app.bundleIdentifier != Bundle.main.bundleIdentifier else { return }
            MainActor.assumeIsolated {
                AppDelegate.previousApp = app
            }
        }

        // Start server
        if (1...65535).contains(config.server.port) {
            activePort = UInt16(config.server.port)
            AppStatus.shared.serverError = server.start(port: activePort)
        } else {
            AppStatus.shared.serverError = "Invalid port: \(config.server.port)"
        }

        // Register hotkey
        HotkeyManager.onHotkey = {
            CommandPicker.shared.show()
        }
        AppStatus.shared.hotkeyError = hotkeyManager.register(hotkey: config.hotkey)
        AppStatus.shared.port = config.server.port
        AppStatus.shared.hotkey = config.hotkey

        // Watch config for changes
        ConfigManager.shared.onChange = { [weak self] in
            guard let self else { return }
            let c = ConfigManager.shared.config
            if (1...65535).contains(c.server.port) {
                let newPort = UInt16(c.server.port)
                if newPort != self.activePort {
                    self.server.stop()
                    AppStatus.shared.serverError = self.server.start(port: newPort)
                    self.activePort = newPort
                }
            } else {
                AppStatus.shared.serverError = "Invalid port: \(c.server.port)"
            }
            AppStatus.shared.hotkeyError = self.hotkeyManager.register(hotkey: c.hotkey)
            AppStatus.shared.port = c.server.port
            AppStatus.shared.hotkey = c.hotkey
            print("[Tetra] Config reloaded")
        }

        // Prompt for Accessibility permission
        Permissions.request(.accessibility)
    }
}

// MARK: - Shared

@MainActor
func runCommand(command: String, text: String) async {
    let task = Task {
        CommandState.shared.isRunning = true
        CommandState.shared.runningCommand = command
        defer {
            CommandState.shared.isRunning = false
            CommandState.shared.runningCommand = nil
            CommandState.shared.runningProcess = nil
            CommandState.shared.runningTask = nil
        }
        do {
            let result = try await CommandRunner.shared.run(command: command, input: text) { process in
                DispatchQueue.main.async { CommandState.shared.runningProcess = process }
            }
            guard !Task.isCancelled else { return }
            TextInjector.inject(result)
        } catch {
            guard !Task.isCancelled else { return }
            AppStatus.shared.lastError = error.localizedDescription
            NSSound.beep()
        }
    }
    CommandState.shared.runningTask = task
    await task.value
}

// MARK: - Menu Bar View

struct MenuBarView: View {
    @State private var launchAtLogin = LoginItem.isEnabled
    @State private var accessibilityGranted = Permissions.isGranted(.accessibility)

    var body: some View {
        let status = AppStatus.shared

        if !accessibilityGranted {
            Button("Grant Accessibility Permission...") {
                Permissions.openSettings(.accessibility)
            }

            Divider()
        }

        if let err = status.configError {
            Section("Config Error") {
                Text(err).font(.caption).foregroundStyle(.red)
                Button("Open Config...") {
                    let path = ConfigDir.url(for: "tetra").appendingPathComponent("config.json")
                    NSWorkspace.shared.open(path)
                }
            }
            Divider()
        }

        if let err = status.serverError {
            Text("Server: \(err)").font(.caption).foregroundStyle(.red)
        }

        if let err = status.hotkeyError {
            Text("Hotkey: \(err)").font(.caption).foregroundStyle(.red)
        }

        if let err = status.lastError {
            Text(err).font(.caption).foregroundStyle(.red)
            Button("Dismiss") { AppStatus.shared.lastError = nil }
        }

        if status.serverError != nil || status.hotkeyError != nil || status.lastError != nil {
            Divider()
        }

        let commands = CommandRunner.shared.listCommands()
        if commands.isEmpty {
            Text("No commands yet").foregroundStyle(.secondary)
            Button("Create Sample Commands...") {
                CommandRunner.shared.createSampleCommands()
            }
        } else if let running = CommandState.shared.runningCommand {
            Text("Running: \(running)...").foregroundStyle(.secondary)
            Button("Cancel") { CommandState.shared.cancel() }
        } else {
            Section("Transform selected text") {
                ForEach(commands, id: \.self) { name in
                    Button(name) { transformSelection(command: name) }
                        .font(.system(.body, design: .monospaced))
                }
            }
        }

        Divider()

        Button("Open Commands Folder...") {
            let dir = CommandRunner.shared.commandsDir
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            NSWorkspace.shared.open(dir)
        }

        Button("Open Config...") {
            let path = ConfigDir.url(for: "tetra").appendingPathComponent("config.json")
            NSWorkspace.shared.open(path)
        }

        Button("Reload Config") {
            ConfigManager.shared.reload()
        }

        Toggle("Start at Login", isOn: $launchAtLogin)
            .onChange(of: launchAtLogin) { _, on in
                if on { LoginItem.enable() } else { LoginItem.disable() }
                launchAtLogin = LoginItem.isEnabled
            }

        Button("About Tetra") {
            NSWorkspace.shared.open(URL(string: "https://apps.vlad.studio/tetra")!)
        }

        Divider()

        if status.serverError == nil {
            Text("Server: localhost:\(status.port)")
        }
        if status.hotkeyError == nil {
            Text("Hotkey: \(status.hotkey)")
        }

        Divider()

        Button("Quit") { NSApp.terminate(nil) }
            .onAppear {
                accessibilityGranted = Permissions.isGranted(.accessibility)
            }
    }

    private func transformSelection(command: String) {
        guard let app = AppDelegate.previousApp else { return }
        app.activate()
        Task {
            try? await Task.sleep(nanoseconds: 200_000_000)
            guard let text = await ContextCapture.captureSelected(), !text.isEmpty else {
                NSSound.beep()
                return
            }
            await runCommand(command: command, text: text)
        }
    }
}
