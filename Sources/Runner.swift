import Foundation
import MacAppKit
import os

enum TetraError: LocalizedError {
    case unknownCommand(String)
    case commandFailed(String, String)
    case commandTimeout(String)
    case tooManyProcesses
    case invalidPrompt(String)
    case unknownLLM(String)
    case llmFailed(String)

    var errorDescription: String? {
        switch self {
        case .unknownCommand(let name): return "Unknown command: \(name)"
        case .commandFailed(let name, let stderr): return "\(name): \(stderr)"
        case .commandTimeout(let name): return "\(name): timed out after 30s"
        case .tooManyProcesses: return "Too many commands running — try again shortly"
        case .invalidPrompt(let msg): return "Invalid prompt: \(msg)"
        case .unknownLLM(let name): return "Unknown LLM: \(name)"
        case .llmFailed(let msg): return "LLM request failed: \(msg)"
        }
    }
}

final class CommandRunner: Sendable {
    static let shared = CommandRunner()

    let commandsDir = ConfigDir.url(for: "tetra").appendingPathComponent("commands")
    private let activeCount = OSAllocatedUnfairLock(initialState: 0)

    func listCommands() -> [String] {
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: commandsDir, includingPropertiesForKeys: nil) else { return [] }
        let names = files
            .filter { !$0.lastPathComponent.hasPrefix(".") }
            .map { commandName(for: $0) }
        return Array(Set(names)).sorted()
    }

    func run(command: String, input: String, args: [String: String] = [:], onProcess: (@Sendable (Process) -> Void)? = nil) async throws -> String {
        let count = activeCount.withLock { $0 += 1; return $0 }
        defer { activeCount.withLock { $0 -= 1 } }
        guard count <= 8 else { throw TetraError.tooManyProcesses }

        guard let commandFile = findCommand(named: command) else {
            throw TetraError.unknownCommand(command)
        }

        if isPromptCommand(commandFile) {
            return try await PromptCommand.run(path: commandFile, input: input, args: args)
        }

        let env = ProcessInfo.processInfo.environment

        let process = Process()
        if let (exec, processArgs) = interpreter(for: commandFile) {
            process.executableURL = URL(fileURLWithPath: exec)
            process.arguments = processArgs
        } else {
            process.executableURL = commandFile
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
                    .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                continuation.resume(returning: result)
            }
        }
    }

    func createSampleCommands() {
        try? FileManager.default.createDirectory(at: commandsDir, withIntermediateDirectories: true)
        writeScript("Uppercase.sh", "#!/bin/bash\ntr '[:lower:]' '[:upper:]'")
        writeScript("Lowercase.sh", "#!/bin/bash\ntr '[:upper:]' '[:lower:]'")
        writeScript("Trim.sh", "#!/bin/bash\nsed 's/^[[:space:]]*//;s/[[:space:]]*$//'")
    }

    private func writeScript(_ name: String, _ content: String) {
        let url = commandsDir.appendingPathComponent(name)
        guard !FileManager.default.fileExists(atPath: url.path) else { return }
        try? content.write(to: url, atomically: true, encoding: .utf8)
        try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
    }

    private func findCommand(named name: String) -> URL? {
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: commandsDir, includingPropertiesForKeys: nil) else { return nil }
        return files
            .filter { !$0.lastPathComponent.hasPrefix(".") }
            .sorted { commandPriority($0) < commandPriority($1) }
            .first { commandName(for: $0) == name }
    }

    private func commandPriority(_ url: URL) -> Int {
        isPromptCommand(url) ? 0 : 1
    }

    private func isPromptCommand(_ url: URL) -> Bool {
        url.lastPathComponent.lowercased().hasSuffix(".prompt.md")
    }

    private func commandName(for url: URL) -> String {
        let name = url.lastPathComponent
        if name.lowercased().hasSuffix(".prompt.md") {
            return String(name.dropLast(".prompt.md".count))
        }
        return url.deletingPathExtension().lastPathComponent
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
