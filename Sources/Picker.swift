import AppKit

@MainActor
final class PickerPanel: NSPanel, NSTextFieldDelegate, NSTableViewDataSource, NSTableViewDelegate {
    static let shared = PickerPanel()

    private let search = NSTextField()
    private let table = NSTableView()
    private var commands: [String] = []
    private var filtered: [String] = []
    private var capturedText: String?

    init() {
        super.init(contentRect: NSRect(x: 0, y: 0, width: 640, height: 400),
                   styleMask: [.titled, .closable, .fullSizeContentView, .utilityWindow],
                   backing: .buffered, defer: false)
        title = "Commands"
        titlebarAppearsTransparent = true
        level = .floating
        isMovableByWindowBackground = true
        isReleasedWhenClosed = false
        animationBehavior = .none
        appearance = NSAppearance(named: .darkAqua)

        let cv = contentView!

        search.placeholderString = "Search commands…"
        search.isBordered = false
        search.focusRingType = .none
        search.drawsBackground = false
        search.delegate = self
        search.translatesAutoresizingMaskIntoConstraints = false
        cv.addSubview(search)

        let sep = NSBox(); sep.boxType = .separator
        sep.translatesAutoresizingMaskIntoConstraints = false
        cv.addSubview(sep)

        let col = NSTableColumn(identifier: .init("c"))
        col.resizingMask = .autoresizingMask
        table.addTableColumn(col)
        table.headerView = nil
        table.dataSource = self
        table.delegate = self
        table.rowHeight = 28
        table.style = .plain
        table.doubleAction = #selector(pick)
        table.target = self

        let scroll = NSScrollView()
        scroll.documentView = table
        scroll.hasVerticalScroller = true
        scroll.translatesAutoresizingMaskIntoConstraints = false
        cv.addSubview(scroll)

        NSLayoutConstraint.activate([
            search.topAnchor.constraint(equalTo: cv.topAnchor, constant: 28),
            search.leadingAnchor.constraint(equalTo: cv.leadingAnchor, constant: 12),
            search.trailingAnchor.constraint(equalTo: cv.trailingAnchor, constant: -12),
            sep.topAnchor.constraint(equalTo: search.bottomAnchor, constant: 6),
            sep.leadingAnchor.constraint(equalTo: cv.leadingAnchor),
            sep.trailingAnchor.constraint(equalTo: cv.trailingAnchor),
            scroll.topAnchor.constraint(equalTo: sep.bottomAnchor),
            scroll.leadingAnchor.constraint(equalTo: cv.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: cv.trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: cv.bottomAnchor),
        ])
    }

    required init?(coder: NSCoder) { fatalError() }

    // MARK: - Show / Dismiss

    func show() {
        Task.detached {
            let text = await ContextCapture.captureSelected()
            await MainActor.run {
                guard let text, !text.isEmpty else { return }
                self.capturedText = text
                self.showPanel()
            }
        }
    }

    private func showPanel() {
        commands = CommandRunner.shared.listCommands()
        guard !commands.isEmpty else { return }
        filtered = commands
        search.stringValue = ""
        table.reloadData()
        if !filtered.isEmpty {
            table.selectRowIndexes([0], byExtendingSelection: false)
        }
        center()
        makeKeyAndOrderFront(nil)
        makeFirstResponder(search)
        NSApp.activate()
    }

    private func dismiss() {
        orderOut(nil)
        capturedText = nil
    }

    @objc private func pick() {
        let row = table.selectedRow
        guard row >= 0, row < filtered.count else { return }
        let command = filtered[row]
        guard let text = capturedText else { return }

        dismiss()
        AppDelegate.previousApp?.activate()

        Task {
            do {
                try await Task.sleep(nanoseconds: 150_000_000)
                let result = try await CommandRunner.shared.run(command: command, input: text)
                TextInjector.inject(result)
            } catch {
                let alert = NSAlert()
                alert.messageText = "Command failed"
                alert.informativeText = error.localizedDescription
                alert.runModal()
            }
        }
    }

    // MARK: - Filtering

    private func refilter() {
        let q = search.stringValue
        filtered = q.isEmpty ? commands : commands.filter { $0.localizedCaseInsensitiveContains(q) }
        table.reloadData()
        if !filtered.isEmpty {
            table.selectRowIndexes([0], byExtendingSelection: false)
        }
    }

    // MARK: - NSTextFieldDelegate

    func controlTextDidChange(_ n: Notification) { refilter() }

    func control(_ control: NSControl, textView: NSTextView,
                 doCommandBy sel: Selector) -> Bool {
        switch sel {
        case #selector(insertNewline(_:)): pick(); return true
        case #selector(cancelOperation(_:)): dismiss(); return true
        case #selector(moveUp(_:)):
            moveSel(max(0, table.selectedRow - 1)); return true
        case #selector(moveDown(_:)):
            moveSel(min(filtered.count - 1, table.selectedRow + 1)); return true
        default: return false
        }
    }

    private func moveSel(_ row: Int) {
        guard row >= 0 else { return }
        table.selectRowIndexes([row], byExtendingSelection: false)
        table.scrollRowToVisible(row)
    }

    // MARK: - NSTableViewDataSource & Delegate

    func numberOfRows(in tableView: NSTableView) -> Int { filtered.count }

    private static let cellID = NSUserInterfaceItemIdentifier("cmd")

    func tableView(_ tv: NSTableView, viewFor col: NSTableColumn?, row: Int) -> NSView? {
        let name = filtered[row]

        if let cell = tv.makeView(withIdentifier: Self.cellID, owner: nil) as? NSTableCellView {
            cell.textField?.stringValue = name
            return cell
        }

        let cell = NSTableCellView()
        cell.identifier = Self.cellID

        let tf = NSTextField(labelWithString: name)
        tf.lineBreakMode = .byTruncatingTail
        tf.translatesAutoresizingMaskIntoConstraints = false
        cell.addSubview(tf)
        cell.textField = tf

        NSLayoutConstraint.activate([
            tf.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 12),
            tf.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -12),
            tf.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
        ])
        return cell
    }
}
