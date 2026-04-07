import AppKit
import MacAppKit

@MainActor
enum TextInjector {
    /// Inject text into the active app via clipboard paste (Cmd+V), then restore clipboard.
    static func inject(_ text: String) {
        let snapshot = ClipboardSnapshot.save()

        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(text, forType: .string)

        // Cmd+V
        let src = CGEventSource(stateID: .hidSystemState)
        guard let down = CGEvent(keyboardEventSource: src, virtualKey: 0x09, keyDown: true),
              let up = CGEvent(keyboardEventSource: src, virtualKey: 0x09, keyDown: false) else { return }
        down.flags = .maskCommand
        up.flags = .maskCommand
        down.post(tap: .cgAnnotatedSessionEventTap)
        up.post(tap: .cgAnnotatedSessionEventTap)

        // Restore clipboard after paste completes
        let changeCount = pb.changeCount
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            MainActor.assumeIsolated {
                if NSPasteboard.general.changeCount == changeCount {
                    snapshot.restore()
                }
            }
        }
    }
}
