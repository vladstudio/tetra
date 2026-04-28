import Foundation
import MacAppKit
import SwiftUI

struct HistoryEntry: Codable, Sendable, Identifiable {
    enum Source: String, Codable, Sendable { case picker, api }

    let timestamp: Date
    let command: String
    let source: Source
    let input: String
    let output: String?
    let error: String?
    let durationMs: Int

    var id: Date { timestamp }
    var ok: Bool { error == nil }
}

@MainActor
@Observable
final class History {
    static let shared = History()
    private(set) var entries: [HistoryEntry] = []
    private let writer: HistoryWriter
    private static let maxEntries = 500
    private static let maxField = 100_000

    private init() {
        let url = ConfigDir.url(for: "tetra").appendingPathComponent("history.jsonl")
        entries = HistoryWriter.loadAndRotate(url: url, max: Self.maxEntries)
        writer = HistoryWriter(url: url)
    }

    func record(command: String, source: HistoryEntry.Source, input: String, output: String?, error: String?, start: Date) {
        let entry = HistoryEntry(
            timestamp: Date(),
            command: command,
            source: source,
            input: String(input.prefix(Self.maxField)),
            output: output.map { String($0.prefix(Self.maxField)) },
            error: error,
            durationMs: Int(Date().timeIntervalSince(start) * 1000)
        )
        entries.insert(entry, at: 0)
        if entries.count > Self.maxEntries { entries.removeLast() }
        Task { await writer.append(entry) }
    }

    func clear() {
        entries.removeAll()
        Task { await writer.clear() }
    }
}

actor HistoryWriter {
    private let url: URL
    private static let encoder: JSONEncoder = {
        let e = JSONEncoder(); e.dateEncodingStrategy = .iso8601; return e
    }()
    private static let decoder: JSONDecoder = {
        let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601; return d
    }()

    init(url: URL) { self.url = url }

    func append(_ entry: HistoryEntry) {
        guard let data = try? Self.encoder.encode(entry) else { return }
        let line = data + Data([0x0A])
        if let h = try? FileHandle(forWritingTo: url) {
            _ = try? h.seekToEnd()
            try? h.write(contentsOf: line)
            try? h.close()
        } else {
            try? line.write(to: url)
        }
    }

    func clear() { try? Data().write(to: url) }

    static func loadAndRotate(url: URL, max: Int) -> [HistoryEntry] {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        let parsed = text.split(separator: "\n").compactMap { line -> HistoryEntry? in
            guard let d = line.data(using: .utf8) else { return nil }
            return try? decoder.decode(HistoryEntry.self, from: d)
        }
        let kept = Array(parsed.suffix(max))
        if kept.count < parsed.count {
            var out = Data()
            for e in kept { if let d = try? encoder.encode(e) { out.append(d); out.append(0x0A) } }
            try? out.write(to: url)
        }
        return Array(kept.reversed())
    }
}
