import AppKit
import SwiftUI

class FunctionPickerPanel {
    static let shared = FunctionPickerPanel()

    private var panel: NSPanel?
    private var capturedText: String?
    private var previousApp: NSRunningApplication?

    func show() {
        previousApp = NSWorkspace.shared.frontmostApplication

        DispatchQueue.global().async {
            let text = HotkeyManager.captureSelectedText()
            DispatchQueue.main.async {
                guard let text = text, !text.isEmpty else { return }
                self.capturedText = text
                self.showPanel()
            }
        }
    }

    private func showPanel() {
        dismiss()

        let functions = Array(ConfigManager.shared.config.functions.keys).sorted()
        guard !functions.isEmpty else { return }

        let state = PickerState()
        let pickerView = PickerView(
            functions: functions,
            state: state,
            onSelect: { [weak self] fn in self?.executeTransform(function: fn, state: state) },
            onDismiss: { [weak self] in self?.dismiss() }
        )

        let hostingView = NSHostingView(rootView: pickerView)
        let w: CGFloat = 260
        let h: CGFloat = 280

        let mouse = NSEvent.mouseLocation
        let frame = NSRect(x: mouse.x - w / 2, y: mouse.y - h, width: w, height: h)

        let p = NSPanel(
            contentRect: frame,
            styleMask: [.titled, .fullSizeContentView, .nonactivatingPanel],
            backing: .buffered, defer: false)
        p.isFloatingPanel = true
        p.level = .floating
        p.titlebarAppearsTransparent = true
        p.titleVisibility = .hidden
        p.isMovableByWindowBackground = true
        p.backgroundColor = .clear
        p.contentView = hostingView
        p.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        panel = p
    }

    private func executeTransform(function: String, state: PickerState) {
        guard let text = capturedText else { return }
        state.isLoading = true

        Task {
            do {
                let result = try await TransformEngine.shared.transform(text: text, function: function)
                await MainActor.run {
                    self.dismiss()
                    if let app = self.previousApp {
                        app.activate()
                    }
                }
                try? await Task.sleep(nanoseconds: 150_000_000)
                await MainActor.run {
                    HotkeyManager.pasteText(result)
                }
            } catch {
                await MainActor.run {
                    state.isLoading = false
                    state.error = error.localizedDescription
                }
            }
        }
    }

    func dismiss() {
        panel?.close()
        panel = nil
        capturedText = nil
    }
}

// MARK: - State

class PickerState: ObservableObject {
    @Published var isLoading = false
    @Published var error: String?
}

// MARK: - SwiftUI View

struct PickerView: View {
    let functions: [String]
    @ObservedObject var state: PickerState
    let onSelect: (String) -> Void
    let onDismiss: () -> Void

    @State private var search = ""
    @State private var selectedIndex = 0
    @State private var monitor: Any?

    var filtered: [String] {
        if search.isEmpty { return functions }
        return functions.filter { $0.localizedCaseInsensitiveContains(search) }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Search field
            TextField("Function...", text: $search)
                .textFieldStyle(.plain)
                .font(.system(size: 15))
                .padding(10)

            Divider()

            if state.isLoading {
                Spacer()
                ProgressView()
                    .scaleEffect(0.8)
                Text("Transforming...")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.top, 4)
                Spacer()
            } else if let error = state.error {
                Spacer()
                Text(error)
                    .font(.caption)
                    .foregroundColor(.red)
                    .padding()
                    .multilineTextAlignment(.center)
                Spacer()
            } else {
                ScrollViewReader { proxy in
                    List(Array(filtered.enumerated()), id: \.element) { index, name in
                        Text(name)
                            .font(.system(size: 13, design: .monospaced))
                            .padding(.vertical, 1)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .listRowBackground(
                                index == selectedIndex
                                    ? Color.accentColor.opacity(0.2)
                                    : Color.clear
                            )
                            .id(name)
                            .onTapGesture { onSelect(name) }
                    }
                    .listStyle(.plain)
                    .onChange(of: selectedIndex) { idx in
                        if filtered.indices.contains(idx) {
                            withAnimation { proxy.scrollTo(filtered[idx]) }
                        }
                    }
                }
            }
        }
        .frame(width: 260, height: 280)
        .background(.ultraThinMaterial)
        .onAppear { installKeyMonitor() }
        .onDisappear { removeKeyMonitor() }
        .onChange(of: search) { _ in selectedIndex = 0 }
    }

    private func installKeyMonitor() {
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            switch Int(event.keyCode) {
            case 125: // down
                if selectedIndex < filtered.count - 1 { selectedIndex += 1 }
                return nil
            case 126: // up
                if selectedIndex > 0 { selectedIndex -= 1 }
                return nil
            case 53: // escape
                onDismiss()
                return nil
            case 36: // return
                if let fn = filtered.indices.contains(selectedIndex) ? filtered[selectedIndex] : nil {
                    onSelect(fn)
                }
                return nil
            default:
                return event
            }
        }
    }

    private func removeKeyMonitor() {
        if let m = monitor { NSEvent.removeMonitor(m) }
    }
}
