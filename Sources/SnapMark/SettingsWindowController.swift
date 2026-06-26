import AppKit

final class SettingsWindowController: NSWindowController, NSWindowDelegate {
    var onShortcutRecordingBegan: (() -> KeyboardShortcut?)?
    var onShortcutRecordingCancelled: (() -> KeyboardShortcut?)?
    var onShortcutChanged: ((KeyboardShortcut) -> Bool)?
    var onSettingsChanged: (() -> Void)?
    var onClose: (() -> Void)?

    private let shortcutButton = ShortcutRecorderButton()
    private let directoryField = NSTextField(labelWithString: "")
    private let languagePopup = NSPopUpButton()
    private let launchAtLoginCheckbox = NSButton(checkboxWithTitle: "", target: nil, action: nil)
    private var didConfigureStableControlConstraints = false

    init() {
        let window = NSWindow(
            contentRect: CGRect(x: 0, y: 0, width: 520, height: 304),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = L10n.text(.settingsTitle)
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
        buildContent()
        reload()
        super.showWindow(sender)
        window?.center()
        window?.makeKeyAndOrderFront(sender)
    }

    func windowWillClose(_ notification: Notification) {
        shortcutButton.stopRecording()
        onClose?()
    }

    private func buildContent() {
        guard let contentView = window?.contentView else { return }
        contentView.subviews.forEach { $0.removeFromSuperview() }
        window?.title = L10n.text(.settingsTitle)
        launchAtLoginCheckbox.title = L10n.text(.settingsLaunchAtLogin)
        configureStableControlConstraints()

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
        rootStack.addArrangedSubview(languageRow())
        rootStack.addArrangedSubview(launchAtLoginRow())
    }

    private func shortcutRow() -> NSView {
        let row = labeledRow(title: L10n.text(.settingsShortcut))
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
        row.addArrangedSubview(shortcutButton)
        return row
    }

    private func directoryRow() -> NSView {
        let row = labeledRow(title: L10n.text(.settingsSaveDirectory))

        directoryField.lineBreakMode = .byTruncatingMiddle
        directoryField.maximumNumberOfLines = 1
        row.addArrangedSubview(directoryField)

        let chooseButton = NSButton(title: L10n.text(.settingsChoose), target: self, action: #selector(chooseDirectory))
        chooseButton.bezelStyle = .rounded
        row.addArrangedSubview(chooseButton)

        return row
    }

    private func languageRow() -> NSView {
        let row = labeledRow(title: L10n.text(.settingsLanguage))
        languagePopup.removeAllItems()
        for setting in AppLanguageSetting.allCases {
            languagePopup.addItem(withTitle: setting.localizedTitle)
            languagePopup.lastItem?.representedObject = setting.rawValue
        }
        languagePopup.target = self
        languagePopup.action = #selector(changeLanguage)
        row.addArrangedSubview(languagePopup)
        return row
    }

    private func launchAtLoginRow() -> NSView {
        let row = labeledRow(title: L10n.text(.settingsLaunchMode))
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

    private func configureStableControlConstraints() {
        guard !didConfigureStableControlConstraints else { return }
        shortcutButton.widthAnchor.constraint(equalToConstant: 210).isActive = true
        directoryField.widthAnchor.constraint(equalToConstant: 270).isActive = true
        languagePopup.widthAnchor.constraint(equalToConstant: 210).isActive = true
        didConfigureStableControlConstraints = true
    }

    private func reload() {
        let settings = AppSettings.shared
        shortcutButton.shortcut = settings.regionShortcut
        directoryField.stringValue = settings.saveDirectory.path
        if let item = languagePopup.itemArray.first(where: { $0.representedObject as? String == settings.languageSetting.rawValue }) {
            languagePopup.select(item)
        }
        launchAtLoginCheckbox.state = LaunchAtLoginService.isEnabled ? .on : .off
    }

    func applyLanguage() {
        buildContent()
        reload()
    }

    @objc private func chooseDirectory() {
        let panel = NSOpenPanel()
        panel.title = L10n.text(.settingsChooseSaveDirectoryTitle)
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

    @objc private func changeLanguage() {
        guard
            let rawValue = languagePopup.selectedItem?.representedObject as? String,
            let setting = AppLanguageSetting(rawValue: rawValue)
        else { return }

        AppSettings.shared.languageSetting = setting
        applyLanguage()
        onSettingsChanged?()
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
        alert.messageText = L10n.text(.settingsLaunchAtLoginErrorTitle)
        alert.informativeText = L10n.text(.settingsLaunchAtLoginErrorMessage)
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
        title = L10n.text(.shortcutRecordingPrompt)
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
        if ExitShortcut.matches(event) {
            stopRecording()
            window?.close()
            return
        }

        guard isRecording else {
            super.keyDown(with: event)
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
