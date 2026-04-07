import Foundation
import MacAppKit

struct TetraConfig: Codable, Sendable {
    var server: ServerConfig = ServerConfig()
    var providers: [String: ProviderConfig] = [:]
    var hotkey: String = "ctrl+option+t"
}

struct ServerConfig: Codable, Sendable {
    var port: Int = 24100
}

struct ProviderConfig: Codable, Sendable {
    var baseUrl: String
    var apiKey: String?

    var resolvedApiKey: String? {
        guard let key = apiKey, !key.isEmpty else { return nil }
        if key.hasPrefix("$") {
            return ProcessInfo.processInfo.environment[String(key.dropFirst())]
        }
        return key
    }
}

class ConfigManager: @unchecked Sendable {
    static let shared = ConfigManager()

    private var _config: TetraConfig = TetraConfig()
    private let lock = NSLock()
    private let configDir: URL
    private let configFile: URL
    private var fileMonitor: DispatchSourceFileSystemObject?
    private var debounceItem: DispatchWorkItem?

    var config: TetraConfig {
        lock.lock()
        defer { lock.unlock() }
        return _config
    }

    @MainActor var onChange: (@MainActor () -> Void)?

    private init() {
        ConfigDir.migrateDirectory(from: "~/.tetra", to: "tetra")
        configDir = ConfigDir.url(for: "tetra")
        configFile = configDir.appendingPathComponent("config.json")
        load()
        watchFile()
    }

    private func load() {
        dispatchPrecondition(condition: .onQueue(.main))
        if !FileManager.default.fileExists(atPath: configFile.path) {
            createDefaultConfig()
        }

        guard let data = try? Data(contentsOf: configFile) else { return }
        do {
            let parsed = try JSONDecoder().decode(TetraConfig.self, from: data)
            lock.lock()
            _config = parsed
            lock.unlock()
            MainActor.assumeIsolated { AppStatus.shared.configError = nil }
        } catch {
            let msg = error.localizedDescription
            print("[Tetra] Config parse error: \(msg)")
            MainActor.assumeIsolated { AppStatus.shared.configError = msg }
        }
    }

    private func createDefaultConfig() {
        try? FileManager.default.createDirectory(at: configDir, withIntermediateDirectories: true)
        let defaultConfig = TetraConfig(
            server: ServerConfig(port: 24100),
            providers: [
                "ollama": ProviderConfig(baseUrl: "http://localhost:11434/v1"),
            ]
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(defaultConfig) {
            try? data.write(to: configFile)
        }
    }

    private func watchFile() {
        // Watch the directory, not the file — editors that do atomic saves
        // (write tmp + rename) invalidate the fd on the old file.
        let fd = open(configDir.path, O_EVTONLY)
        guard fd >= 0 else { return }
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd, eventMask: [.write, .rename], queue: .main)
        source.setEventHandler { [weak self] in
            guard let self else { return }
            self.debounceItem?.cancel()
            let item = DispatchWorkItem { [weak self] in
                guard let self else { return }
                self.load()
                MainActor.assumeIsolated { self.onChange?() }
            }
            self.debounceItem = item
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2, execute: item)
        }
        source.setCancelHandler { close(fd) }
        source.resume()
        fileMonitor = source
    }
}
