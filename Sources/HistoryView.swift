import AppKit
import SwiftUI

struct HistoryView: View {
    @State private var selection: Date?

    var body: some View {
        let entries = History.shared.entries
        NavigationSplitView {
            List(entries, selection: $selection) { entry in
                row(entry)
            }
            .navigationSplitViewColumnWidth(min: 240, ideal: 280)
            .toolbar {
                Button("Clear", role: .destructive) {
                    History.shared.clear(); selection = nil
                }
                .disabled(entries.isEmpty)
            }
        } detail: {
            if let id = selection, let e = entries.first(where: { $0.id == id }) {
                detail(e)
            } else {
                ContentUnavailableView("Select an entry", systemImage: "list.bullet.rectangle")
            }
        }
        .navigationTitle("History")
    }

    private func row(_ e: HistoryEntry) -> some View {
        HStack {
            Image(systemName: e.ok ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundStyle(e.ok ? .green : .red)
            VStack(alignment: .leading) {
                Text(e.command).font(.headline)
                Text(e.timestamp, format: .dateTime.month().day().hour().minute().second())
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Text(e.source.rawValue).font(.caption2).foregroundStyle(.secondary)
        }
    }

    private func detail(_ e: HistoryEntry) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text(e.command).font(.title2.bold())
                    Spacer()
                    Text("\(e.durationMs) ms · \(e.source.rawValue)")
                        .font(.caption).foregroundStyle(.secondary)
                }
                section("Input", text: e.input)
                if let out = e.output { section("Output", text: out) }
                if let err = e.error { section("Error", text: err, color: .red) }
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func section(_ title: String, text: String, color: Color = .primary) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title).font(.subheadline.bold())
                Button("Copy") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(text, forType: .string)
                }
                .buttonStyle(.borderless).font(.caption)
            }
            Text(text)
                .font(.system(.body, design: .monospaced))
                .foregroundStyle(color)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8)
                .background(Color(nsColor: .textBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 6))
        }
    }
}
