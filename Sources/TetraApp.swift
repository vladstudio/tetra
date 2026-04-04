import ServiceManagement
import SwiftUI

@main
struct TetraApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate

    private static let menuBarIcon: NSImage = {
        if let url = Bundle.module.url(forResource: "MenuBarIcon", withExtension: "png"),
           let img = NSImage(contentsOf: url)
        {
            img.size = NSSize(width: 18, height: 18)
            img.isTemplate = true
            return img
        }
        return NSImage(systemSymbolName: "text.cursor", accessibilityDescription: "Tetra")!
    }()

    var body: some Scene {
        MenuBarExtra {
            MenuBarView()
        } label: {
            Image(nsImage: Self.menuBarIcon)
        }
    }
}

// MARK: - AppDelegate

class AppDelegate: NSObject, NSApplicationDelegate {
    @MainActor static var previousApp: NSRunningApplication?
    private var server = TetraServer()
    private var hotkeyManager = HotkeyManager()

    func applicationDidFinishLaunching(_ notification: Notification) {
        CommandRunner.shared.createDefaults()
        let config = ConfigManager.shared.config

        // Track the last non-Tetra frontmost app
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
        server.start(port: UInt16(config.server.port))

        // Register hotkey
        HotkeyManager.onHotkey = {
            PickerPanel.shared.show()
        }
        hotkeyManager.register(hotkey: config.hotkey)

        // Watch config for changes
        ConfigManager.shared.onChange = { [weak self] in
            guard let self else { return }
            let c = ConfigManager.shared.config
            self.server.stop()
            self.server.start(port: UInt16(c.server.port))
            self.hotkeyManager.register(hotkey: c.hotkey)
            print("[Tetra] Config reloaded")
        }

        // Prompt for Accessibility permission
        let opts = ["AXTrustedCheckOptionPrompt" as CFString: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(opts)
    }
}

// MARK: - Menu Bar View

struct MenuBarView: View {
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled

    var body: some View {
        let config = ConfigManager.shared.config

        Section("Commands") {
            ForEach(CommandRunner.shared.listCommands(), id: \.self) { name in
                Button(name) {
                    transformSelection(command: name)
                }
                .font(.system(.body, design: .monospaced))
            }
        }

        Divider()

        Text("Server: localhost:\(config.server.port)")
            .font(.caption)
        Text("Hotkey: \(config.hotkey)")
            .font(.caption)

        Divider()

        Button("Open Commands Folder...") {
            NSWorkspace.shared.open(CommandRunner.shared.commandsDir)
        }

        Button("Open Config...") {
            let path = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(".tetra/config.json")
            NSWorkspace.shared.open(path)
        }

        Toggle("Start at Login", isOn: $launchAtLogin)
            .onChange(of: launchAtLogin) { _, on in
                do {
                    if on { try SMAppService.mainApp.register() }
                    else { try SMAppService.mainApp.unregister() }
                } catch {
                    launchAtLogin = !on
                }
            }

        Divider()

        Button("Quit") { NSApp.terminate(nil) }
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
            do {
                let result = try await CommandRunner.shared.run(command: command, input: text)
                TextInjector.inject(result)
            } catch {
                let alert = NSAlert()
                alert.messageText = "Command failed"
                alert.informativeText = error.localizedDescription
                alert.runModal()
            }
        }
    }
}
