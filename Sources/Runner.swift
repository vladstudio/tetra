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

    func run(command: String, input: String) async throws -> String {
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

    func createDefaults() {
        guard !FileManager.default.fileExists(atPath: commandsDir.path) else { return }
        try? FileManager.default.createDirectory(at: commandsDir, withIntermediateDirectories: true)

        let defaults: [(String, String)] = [
            ("uppercase.sh", """
            #!/bin/bash
            tr '[:lower:]' '[:upper:]'
            """),
            ("lowercase.sh", """
            #!/bin/bash
            tr '[:upper:]' '[:lower:]'
            """),
            ("trim.sh", """
            #!/bin/bash
            sed 's/^[[:space:]]*//;s/[[:space:]]*$//'
            """),
            ("fix-grammar.py", """
            #!/usr/bin/env python3
            # Fix grammar using Ollama (requires Ollama running locally)
            import sys, os, json, urllib.request

            text = sys.stdin.read()
            url = os.environ.get("TETRA_OLLAMA_URL", "http://localhost:11434/v1") + "/chat/completions"

            body = json.dumps({
                "model": "gemma3:4b",
                "messages": [
                    {"role": "system", "content": "Fix grammar and spelling. Return ONLY the corrected text."},
                    {"role": "user", "content": text}
                ],
                "temperature": 0.3
            }).encode()

            req = urllib.request.Request(url, data=body, headers={"Content-Type": "application/json"})
            resp = urllib.request.urlopen(req, timeout=60)
            result = json.loads(resp.read())
            print(result["choices"][0]["message"]["content"].strip())
            """),
        ]

        for (name, content) in defaults {
            let path = commandsDir.appendingPathComponent(name)
            try? content.write(to: path, atomically: true, encoding: .utf8)
            try? FileManager.default.setAttributes(
                [.posixPermissions: 0o755], ofItemAtPath: path.path)
        }
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
