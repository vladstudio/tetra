import AppKit
import SwiftUI

@MainActor
class PickerPanel {
    static let shared = PickerPanel()

    private var panel: NSPanel?
    private var capturedText: String?

    func show() {
        Task.detached {
            let text = ContextCapture.captureSelected()
            await MainActor.run {
                guard let text, !text.isEmpty else { return }
                self.capturedText = text
                self.showPanel()
            }
        }
    }

    private func showPanel() {
        dismiss()

        let commands = CommandRunner.shared.listCommands()
        guard !commands.isEmpty else { return }

        let state = PickerState()
        let pickerView = PickerView(
            commands: commands,
            state: state,
            onSelect: { [weak self] cmd in self?.executeCommand(cmd, state: state) },
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
        NSApp.activate()

        panel = p
    }

    private func executeCommand(_ command: String, state: PickerState) {
        guard let text = capturedText else { return }
        state.isLoading = true

        Task {
            do {
                let result = try await CommandRunner.shared.run(command: command, input: text)
                self.dismiss()
                AppDelegate.previousApp?.activate()
                try? await Task.sleep(nanoseconds: 150_000_000)
                TextInjector.inject(result)
            } catch {
                state.isLoading = false
                state.error = error.localizedDescription
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

@MainActor
class PickerState: ObservableObject {
    @Published var isLoading = false
    @Published var error: String?
}

// MARK: - SwiftUI View

struct PickerView: View {
    let commands: [String]
    @ObservedObject var state: PickerState
    let onSelect: @MainActor (String) -> Void
    let onDismiss: @MainActor () -> Void

    @State private var search = ""
    @State private var selectedIndex = 0
    @State private var monitor: Any?

    var filtered: [String] {
        if search.isEmpty { return commands }
        return commands.filter { $0.localizedCaseInsensitiveContains(search) }
    }

    var body: some View {
        VStack(spacing: 0) {
            TextField("Command...", text: $search)
                .textFieldStyle(.plain)
                .font(.system(size: 15))
                .padding(10)

            Divider()

            if state.isLoading {
                Spacer()
                ProgressView()
                    .scaleEffect(0.8)
                Text("Running...")
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
                    .onChange(of: selectedIndex) { _, idx in
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
        .onChange(of: search) { _, _ in selectedIndex = 0 }
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
                if filtered.indices.contains(selectedIndex) {
                    onSelect(filtered[selectedIndex])
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
