import Foundation

struct TetraConfig: Codable {
    var server: ServerConfig = ServerConfig()
    var providers: [String: ProviderConfig] = [:]
    var functions: [String: FunctionConfig] = [:]
    var hotkey: String = "ctrl+option+t"
}

struct ServerConfig: Codable {
    var port: Int = 24100
}

struct ProviderConfig: Codable {
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

struct FunctionConfig: Codable {
    var type: String // "builtin" or "llm"
    // builtin
    var transform: String?
    // llm
    var provider: String?
    var model: String?
    var system: String?
    var prompt: String? // must contain {{text}}
    var temperature: Double?
    var maxTokens: Int?
}

class ConfigManager {
    static let shared = ConfigManager()

    private var _config: TetraConfig = TetraConfig()
    private let lock = NSLock()
    private let configDir: URL
    private let configFile: URL
    private var fileMonitor: DispatchSourceFileSystemObject?

    var config: TetraConfig {
        lock.lock()
        defer { lock.unlock() }
        return _config
    }

    var onChange: (() -> Void)?

    private init() {
        configDir = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".tetra")
        configFile = configDir.appendingPathComponent("config.json")
        load()
        watchFile()
    }

    func load() {
        if !FileManager.default.fileExists(atPath: configFile.path) {
            createDefaultConfig()
        }

        guard let data = try? Data(contentsOf: configFile),
              let parsed = try? JSONDecoder().decode(TetraConfig.self, from: data) else { return }
        lock.lock()
        _config = parsed
        lock.unlock()
    }

    private func createDefaultConfig() {
        try? FileManager.default.createDirectory(at: configDir, withIntermediateDirectories: true)
        let defaultConfig = TetraConfig(
            server: ServerConfig(port: 24100),
            providers: [
                "ollama": ProviderConfig(baseUrl: "http://localhost:11434/v1"),
            ],
            functions: [
                "uppercase": FunctionConfig(type: "builtin", transform: "uppercase"),
                "lowercase": FunctionConfig(type: "builtin", transform: "lowercase"),
                "trim": FunctionConfig(type: "builtin", transform: "trim"),
            ]
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(defaultConfig) {
            try? data.write(to: configFile)
        }
    }

    private func watchFile() {
        let fd = open(configDir.path, O_EVTONLY)
        guard fd >= 0 else { return }
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd, eventMask: [.write, .rename], queue: .main)
        source.setEventHandler { [weak self] in
            self?.load()
            self?.onChange?()
        }
        source.setCancelHandler { close(fd) }
        source.resume()
        fileMonitor = source
    }
}
