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
    private var server = TetraServer()
    private var hotkeyManager = HotkeyManager()

    func applicationDidFinishLaunching(_ notification: Notification) {
        let config = ConfigManager.shared.config

        // Start server
        server.start(port: UInt16(config.server.port))

        // Register hotkey
        HotkeyManager.onHotkey = {
            DispatchQueue.main.async {
                FunctionPickerPanel.shared.show()
            }
        }
        hotkeyManager.register(hotkey: config.hotkey)

        // Watch config for changes
        ConfigManager.shared.onChange = { [weak self] in
            guard let self = self else { return }
            let c = ConfigManager.shared.config
            self.server.stop()
            self.server.start(port: UInt16(c.server.port))
            self.hotkeyManager.register(hotkey: c.hotkey)
            print("[tetra] Config reloaded")
        }

        // Prompt for Accessibility permission
        let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(opts)
    }
}

// MARK: - Menu Bar View

struct MenuBarView: View {
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled

    var body: some View {
        let config = ConfigManager.shared.config

        Section("Functions") {
            ForEach(Array(config.functions.keys).sorted(), id: \.self) { name in
                let fn = config.functions[name]!
                Text("\(name)  (\(fn.type))")
                    .font(.system(.body, design: .monospaced))
            }
        }

        Divider()

        Text("Server: localhost:\(config.server.port)")
            .font(.caption)
        Text("Hotkey: \(config.hotkey)")
            .font(.caption)

        Divider()

        Button("Open Config...") {
            let path = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(".tetra/config.json")
            NSWorkspace.shared.open(path)
        }

        Toggle("Start at Login", isOn: $launchAtLogin)
            .onChange(of: launchAtLogin) { on in
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
}
