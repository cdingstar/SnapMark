import AppKit

final class SettingsWindowController: NSWindowController, NSWindowDelegate {
    var onShortcutRecordingBegan: (() -> KeyboardShortcut?)?
    var onShortcutRecordingCancelled: (() -> KeyboardShortcut?)?
    var onShortcutChanged: ((KeyboardShortcut) -> Bool)?
    var onSettingsChanged: (() -> Void)?

    private let shortcutButton = ShortcutRecorderButton()
    private let directoryField = NSTextField(labelWithString: "")
    private let launchAtLoginCheckbox = NSButton(checkboxWithTitle: "允许自动开机启动", target: nil, action: nil)

    init() {
        let window = NSWindow(
            contentRect: CGRect(x: 0, y: 0, width: 520, height: 250),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "设置"
        window.isReleasedWhenClosed = false
        super.init(window: window)
        window.delegate = self
        buildContent()
        reload()
    }

    required init?(coder: NSCoder) {
        nil
    }

    override func showWindow(_ sender: Any?) {
        reload()
        super.showWindow(sender)
        window?.center()
        window?.makeKeyAndOrderFront(sender)
    }

    func windowWillClose(_ notification: Notification) {
        shortcutButton.stopRecording()
    }

    private func buildContent() {
        guard let contentView = window?.contentView else { return }

        let rootStack = NSStackView()
        rootStack.orientation = .vertical
        rootStack.alignment = .leading
        rootStack.spacing = 18
        rootStack.translatesAutoresizingMaskIntoConstraints = false

        contentView.addSubview(rootStack)

        NSLayoutConstraint.activate([
            rootStack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 24),
            rootStack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -24),
            rootStack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 24),
            rootStack.bottomAnchor.constraint(lessThanOrEqualTo: contentView.bottomAnchor, constant: -24)
        ])

        rootStack.addArrangedSubview(shortcutRow())
        rootStack.addArrangedSubview(directoryRow())
        rootStack.addArrangedSubview(launchAtLoginRow())
    }

    private func shortcutRow() -> NSView {
        let row = labeledRow(title: "快捷键")
        shortcutButton.bezelStyle = .rounded
        shortcutButton.alignment = .center
        shortcutButton.target = shortcutButton
        shortcutButton.action = #selector(ShortcutRecorderButton.beginRecording)
        shortcutButton.onRecordingBegin = { [weak self] in
            self?.onShortcutRecordingBegan?()
        }
        shortcutButton.onRecordingCancel = { [weak self] in
            self?.onShortcutRecordingCancelled?()
        }
        shortcutButton.onShortcutChange = { [weak self] shortcut in
            guard let self else { return false }
            let didApply = self.onShortcutChanged?(shortcut) ?? false
            if didApply {
                self.shortcutButton.shortcut = shortcut
            }
            return didApply
        }
        shortcutButton.widthAnchor.constraint(equalToConstant: 210).isActive = true
        row.addArrangedSubview(shortcutButton)
        return row
    }

    private func directoryRow() -> NSView {
        let row = labeledRow(title: "存储目录")

        directoryField.lineBreakMode = .byTruncatingMiddle
        directoryField.maximumNumberOfLines = 1
        directoryField.widthAnchor.constraint(equalToConstant: 270).isActive = true
        row.addArrangedSubview(directoryField)

        let chooseButton = NSButton(title: "选择...", target: self, action: #selector(chooseDirectory))
        chooseButton.bezelStyle = .rounded
        row.addArrangedSubview(chooseButton)

        return row
    }

    private func launchAtLoginRow() -> NSView {
        let row = labeledRow(title: "启动方式")
        launchAtLoginCheckbox.target = self
        launchAtLoginCheckbox.action = #selector(toggleLaunchAtLogin)
        row.addArrangedSubview(launchAtLoginCheckbox)
        return row
    }

    private func labeledRow(title: String) -> NSStackView {
        let row = NSStackView()
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 12
        row.translatesAutoresizingMaskIntoConstraints = false

        let label = NSTextField(labelWithString: title)
        label.font = .systemFont(ofSize: 13, weight: .medium)
        label.widthAnchor.constraint(equalToConstant: 72).isActive = true
        row.addArrangedSubview(label)

        return row
    }

    private func reload() {
        let settings = AppSettings.shared
        shortcutButton.shortcut = settings.regionShortcut
        directoryField.stringValue = settings.saveDirectory.path
        launchAtLoginCheckbox.state = LaunchAtLoginService.isEnabled ? .on : .off
    }

    @objc private func chooseDirectory() {
        let panel = NSOpenPanel()
        panel.title = "选择自动保存目录"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.directoryURL = AppSettings.shared.saveDirectory

        panel.beginSheetModal(for: window!) { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            AppSettings.shared.saveDirectory = url
            self?.directoryField.stringValue = url.path
            self?.onSettingsChanged?()
        }
    }

    @objc private func toggleLaunchAtLogin() {
        let enabled = launchAtLoginCheckbox.state == .on

        do {
            try LaunchAtLoginService.setEnabled(enabled)
            launchAtLoginCheckbox.state = LaunchAtLoginService.isEnabled ? .on : .off
        } catch {
            launchAtLoginCheckbox.state = LaunchAtLoginService.isEnabled ? .on : .off
            presentLaunchAtLoginError(error)
        }
    }

    private func presentLaunchAtLoginError(_ error: Error) {
        let alert = NSAlert(error: error)
        alert.messageText = "开机启动设置失败"
        alert.informativeText = "请确认 SnapMark 是从 .app 包运行，而不是从命令行临时进程运行。"
        if let window {
            alert.beginSheetModal(for: window)
        } else {
            alert.runModal()
        }
    }
}

final class ShortcutRecorderButton: NSButton {
    var shortcut: KeyboardShortcut = .defaultRegion {
        didSet {
            if !isRecording {
                title = shortcut.displayString
            }
        }
    }

    var onRecordingBegin: (() -> KeyboardShortcut?)?
    var onRecordingCancel: (() -> KeyboardShortcut?)?
    var onShortcutChange: ((KeyboardShortcut) -> Bool)?

    private var isRecording = false

    override var acceptsFirstResponder: Bool {
        true
    }

    @objc func beginRecording() {
        guard !isRecording else { return }
        if let activeShortcut = onRecordingBegin?() {
            shortcut = activeShortcut
        }
        isRecording = true
        title = "请按新的快捷键"
        window?.makeFirstResponder(self)
    }

    func stopRecording() {
        guard isRecording else {
            title = shortcut.displayString
            return
        }
        isRecording = false
        if let activeShortcut = onRecordingCancel?() {
            shortcut = activeShortcut
        }
        title = shortcut.displayString
    }

    override func keyDown(with event: NSEvent) {
        guard isRecording else {
            super.keyDown(with: event)
            return
        }

        if event.keyCode == 53 {
            stopRecording()
            return
        }

        guard let newShortcut = KeyboardShortcut.from(event: event) else {
            NSSound.beep()
            return
        }

        if onShortcutChange?(newShortcut) == true {
            isRecording = false
            title = newShortcut.displayString
        } else {
            NSSound.beep()
            stopRecording()
        }
    }
}
