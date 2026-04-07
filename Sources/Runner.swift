import Foundation
import MacAppKit
import os

enum TetraError: LocalizedError {
    case unknownCommand(String)
    case commandFailed(String, String)
    case commandTimeout(String)

    var errorDescription: String? {
        switch self {
        case .unknownCommand(let name): return "Unknown command: \(name)"
        case .commandFailed(let name, let stderr): return "\(name): \(stderr)"
        case .commandTimeout(let name): return "\(name): timed out after 30s"
        }
    }
}

final class CommandRunner: Sendable {
    static let shared = CommandRunner()

    let commandsDir = ConfigDir.url(for: "tetra").appendingPathComponent("commands")

    func listCommands() -> [String] {
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: commandsDir, includingPropertiesForKeys: nil) else { return [] }
        return files
            .filter { !$0.lastPathComponent.hasPrefix(".") }
            .map { $0.deletingPathExtension().lastPathComponent }
            .sorted()
    }

    func run(command: String, input: String, extraEnv: [String: String]? = nil, onProcess: (@Sendable (Process) -> Void)? = nil) async throws -> String {
        guard let script = findScript(named: command) else {
            throw TetraError.unknownCommand(command)
        }

        var env = ProcessInfo.processInfo.environment
        for (name, provider) in ConfigManager.shared.config.providers {
            let prefix = "TETRA_\(name.uppercased())"
            env["\(prefix)_URL"] = provider.baseUrl
            if let key = provider.resolvedApiKey {
                env["\(prefix)_KEY"] = key
            }
        }
        if let extraEnv { env.merge(extraEnv) { _, new in new } }

        let process = Process()
        if let (exec, args) = interpreter(for: script) {
            process.executableURL = URL(fileURLWithPath: exec)
            process.arguments = args
        } else {
            process.executableURL = script
        }
        process.environment = env

        let stdinPipe = Pipe()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardInput = stdinPipe
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        try process.run()
        onProcess?(process)

        stdinPipe.fileHandleForWriting.write(Data(input.utf8))
        stdinPipe.fileHandleForWriting.closeFile()

        // Run blocking I/O off the cooperative thread pool
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global().async {
                // Kill process after 30 seconds
                let timedOut = OSAllocatedUnfairLock(initialState: false)
                let timeoutItem = DispatchWorkItem {
                    timedOut.withLock { $0 = true }
                    process.terminate()
                    DispatchQueue.global().asyncAfter(deadline: .now() + 2) {
                        if process.isRunning { kill(process.processIdentifier, SIGKILL) }
                    }
                }
                DispatchQueue.global().asyncAfter(deadline: .now() + 30, execute: timeoutItem)

                // Read both pipes concurrently to avoid deadlock.
                // Each var is written exactly once, and group.wait() synchronizes before reads.
                nonisolated(unsafe) var outData = Data()
                nonisolated(unsafe) var errData = Data()
                let group = DispatchGroup()
                group.enter()
                DispatchQueue.global().async {
                    outData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
                    group.leave()
                }
                group.enter()
                DispatchQueue.global().async {
                    errData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
                    group.leave()
                }
                group.wait()
                process.waitUntilExit()
                timeoutItem.cancel()

                if process.terminationStatus != 0 {
                    if timedOut.withLock({ $0 }) {
                        continuation.resume(throwing: TetraError.commandTimeout(command))
                    } else {
                        let stderr = String(data: errData, encoding: .utf8) ?? ""
                        continuation.resume(throwing: TetraError.commandFailed(command, stderr))
                    }
                    return
                }

                let result = String(data: outData, encoding: .utf8)?
                    .trimmingCharacters(in: .newlines) ?? ""
                continuation.resume(returning: result)
            }
        }
    }

    func createSampleCommands() {
        try? FileManager.default.createDirectory(at: commandsDir, withIntermediateDirectories: true)
        writeScript("Uppercase.sh", "#!/bin/bash\ntr '[:lower:]' '[:upper:]'")
        writeScript("Lowercase.sh", "#!/bin/bash\ntr '[:upper:]' '[:lower:]'")
        writeScript("Trim.sh", "#!/bin/bash\nsed 's/^[[:space:]]*//;s/[[:space:]]*$//'")
        if let (name, body) = detectGrammarScript() { writeScript(name, body) }
    }

    private func writeScript(_ name: String, _ content: String) {
        let url = commandsDir.appendingPathComponent(name)
        guard !FileManager.default.fileExists(atPath: url.path) else { return }
        try? content.write(to: url, atomically: true, encoding: .utf8)
        try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
    }

    private func detectGrammarScript() -> (String, String)? {
        let env = ProcessInfo.processInfo.environment
        let oai: [(key: String, prefix: String, model: String)] = [
            ("OPENROUTER_API_KEY", "OPENROUTER", "google/gemma-4-26b-a4b-it"),
            ("GEMINI_API_KEY",     "GEMINI",     "gemini-2.5-flash-lite"),
            ("OPENAI_API_KEY",     "OPENAI",     "gpt-4.1-mini"),
            ("GROQ_API_KEY",       "GROQ",       "llama-3.3-70b-versatile"),
        ]
        let sys = "Fix grammar and spelling. Return ONLY the corrected text."
        if let p = oai.first(where: { !(env[$0.key] ?? "").isEmpty }) {
            return ("Fix grammar.sh", """
            #!/bin/bash
            jq -Rsn --arg t "$(cat)" '{"model":"\(p.model)","messages":[{"role":"system","content":"\(sys)"},{"role":"user","content":$t}],"temperature":0.3}' \
            | curl -s "$TETRA_\(p.prefix)_URL/chat/completions" -H "Content-Type: application/json" -H "Authorization: Bearer $TETRA_\(p.prefix)_KEY" -d @- \
            | jq -r '.choices[0].message.content'
            """)
        }
        if !(env["ANTHROPIC_API_KEY"] ?? "").isEmpty {
            return ("Fix grammar.sh", """
            #!/bin/bash
            jq -Rsn --arg t "$(cat)" '{"model":"claude-haiku-4-5-20251001","max_tokens":1024,"system":"\(sys)","messages":[{"role":"user","content":$t}]}' \
            | curl -s "$TETRA_ANTHROPIC_URL/v1/messages" -H "Content-Type: application/json" -H "x-api-key: $TETRA_ANTHROPIC_KEY" -H "anthropic-version: 2023-06-01" -d @- \
            | jq -r '.content[0].text'
            """)
        }
        return nil
    }

    private func findScript(named name: String) -> URL? {
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: commandsDir, includingPropertiesForKeys: nil) else { return nil }
        return files.first { $0.deletingPathExtension().lastPathComponent == name }
    }

    private func interpreter(for path: URL) -> (String, [String])? {
        switch path.pathExtension.lowercased() {
        case "sh", "bash": return ("/bin/bash", [path.path])
        case "py":         return ("/usr/bin/env", ["python3", path.path])
        case "rb":         return ("/usr/bin/env", ["ruby", path.path])
        case "js":         return ("/usr/bin/env", ["node", path.path])
        default:           return nil
        }
    }
}
