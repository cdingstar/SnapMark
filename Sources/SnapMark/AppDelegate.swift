import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private static let authorContactEmail = "cdingstar@gmail.com"

    private let captureService = ScreenCaptureService()
    private let hotKeyManager = HotKeyManager()
    private var statusItem: NSStatusItem?
    private var regionMenuItem: NSMenuItem?
    private var fullScreenMenuItem: NSMenuItem?
    private var openFolderMenuItem: NSMenuItem?
    private var settingsMenuItem: NSMenuItem?
    private var aboutMenuItem: NSMenuItem?
    private var quitMenuItem: NSMenuItem?
    private var registeredRegionShortcut: KeyboardShortcut?
    private var recordingPreviousRegionShortcut: KeyboardShortcut?
    private var isRecordingRegionShortcut = false
    private var unresponsiveRegionShortcuts: Set<KeyboardShortcut> = []
    private var lastRegionHotKeyFireDate = Date.distantPast
    private var isRecoveringRegionHotKey = false
    private var globalHotKeyHealthMonitor: Any?
    private var localHotKeyHealthMonitor: Any?
    private var globalResetMonitor: Any?
    private var localResetMonitor: Any?
    private var statusTipPopover: NSPopover?
    private var settingsWindowController: SettingsWindowController?
    private var selectionController: ScreenSelectionController?
    private var editorWindows: [EditorWindowController] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        configureStatusItem()
        configureHotKeys()
        configureHotKeyHealthMonitor()
        configureResetMonitor()
    }

    func applicationWillTerminate(_ notification: Notification) {
        closeAllTransientContexts()

        if let globalHotKeyHealthMonitor {
            NSEvent.removeMonitor(globalHotKeyHealthMonitor)
        }
        if let localHotKeyHealthMonitor {
            NSEvent.removeMonitor(localHotKeyHealthMonitor)
        }
        if let globalResetMonitor {
            NSEvent.removeMonitor(globalResetMonitor)
        }
        if let localResetMonitor {
            NSEvent.removeMonitor(localResetMonitor)
        }
    }

    private func configureStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        let statusImage = NSImage(named: "StatusIcon") ?? NSImage(systemSymbolName: "camera.viewfinder", accessibilityDescription: "SnapMark")
        statusImage?.size = NSSize(width: 20, height: 20)
        statusImage?.isTemplate = false
        item.button?.image = statusImage
        item.button?.imageScaling = .scaleProportionallyDown
        item.button?.imagePosition = .imageOnly
        item.button?.title = ""

        let menu = NSMenu()
        let regionItem = menuItem(
            title: L10n.text(.menuRegionCapture),
            action: #selector(captureRegion),
            keyEquivalent: "",
            symbolName: "rectangle.dashed"
        )
        regionMenuItem = regionItem
        menu.addItem(regionItem)

        let fullScreenItem = menuItem(
            title: L10n.text(.menuFullScreenCapture),
            action: #selector(captureFullScreen),
            keyEquivalent: "",
            symbolName: "display"
        )
        fullScreenMenuItem = fullScreenItem
        menu.addItem(fullScreenItem)
        menu.addItem(NSMenuItem.separator())
        let openFolderItem = menuItem(
            title: L10n.text(.menuOpenAutoSaveFolder),
            action: #selector(openAutoSaveFolder),
            keyEquivalent: "o",
            symbolName: "folder"
        )
        openFolderMenuItem = openFolderItem
        menu.addItem(openFolderItem)
        let settingsItem = menuItem(
            title: L10n.text(.menuSettings),
            action: #selector(openSettings),
            keyEquivalent: "",
            symbolName: "gearshape"
        )
        settingsMenuItem = settingsItem
        menu.addItem(settingsItem)
        let aboutItem = menuItem(
            title: L10n.format(.menuAboutFormat, AppVersion.aboutVersionText),
            action: #selector(showAbout),
            keyEquivalent: "",
            symbolName: "info.circle"
        )
        aboutMenuItem = aboutItem
        menu.addItem(aboutItem)
        menu.addItem(NSMenuItem.separator())
        let quitItem = menuItem(
            title: L10n.text(.menuQuit),
            action: #selector(quit),
            keyEquivalent: "q",
            symbolName: "power"
        )
        quitMenuItem = quitItem
        menu.addItem(quitItem)

        menu.items.forEach { $0.target = self }
        item.menu = menu
        statusItem = item
        updateStatusMetadata()
    }

    private func menuItem(title: String, action: Selector, keyEquivalent: String, symbolName: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: keyEquivalent)
        item.image = menuIcon(symbolName)
        return item
    }

    private func menuIcon(_ symbolName: String) -> NSImage? {
        let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)
        image?.isTemplate = true
        image?.size = NSSize(width: 16, height: 16)
        return image
    }

    private func configureHotKeys() {
        let savedShortcut = AppSettings.shared.regionShortcut

        guard AppSettings.shared.hasStoredRegionShortcut else {
            configureFallbackRegionHotKey(
                candidates: KeyboardShortcut.fallbackRegionShortcuts,
                failedResults: []
            )
            return
        }

        let result = hotKeyManager.register(
            regionShortcut: savedShortcut,
            region: { [weak self] in self?.handleRegionHotKey() }
        )

        if result.isRegistered {
            registeredRegionShortcut = savedShortcut
            updateStatusMetadata()
        } else {
            if savedShortcut.isFallbackCandidate {
                configureFallbackRegionHotKey(
                    candidates: KeyboardShortcut.fallbackRegionShortcuts.filter { $0 != savedShortcut },
                    failedResults: [(savedShortcut, result)]
                )
                return
            }

            registeredRegionShortcut = nil
            updateStatusMetadata()
            showStartupShortcutConflict(savedShortcut, result: result)
        }
    }

    private func configureFallbackRegionHotKey(candidates: [KeyboardShortcut], failedResults initialFailedResults: [(KeyboardShortcut, HotKeyRegistrationResult)]) {
        var failedResults = initialFailedResults

        for shortcut in candidates {
            let result: HotKeyRegistrationResult
            if registeredRegionShortcut == nil, failedResults.isEmpty {
                result = hotKeyManager.register(
                    regionShortcut: shortcut,
                    region: { [weak self] in self?.handleRegionHotKey() }
                )
            } else {
                result = hotKeyManager.updateRegionShortcut(shortcut)
            }

            if result.isRegistered {
                AppSettings.shared.regionShortcut = shortcut
                registeredRegionShortcut = shortcut
                updateStatusMetadata()

                if !failedResults.isEmpty {
                    showStartupFallbackNotice(failedResults: failedResults, activeShortcut: shortcut)
                }
                return
            }

            failedResults.append((shortcut, result))
        }

        registeredRegionShortcut = nil
        updateStatusMetadata()
        showNoAvailableShortcutTip(failedResults: failedResults)
    }

    private func configureHotKeyHealthMonitor() {
        globalHotKeyHealthMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.observePotentialRegionHotKey(event)
        }

        localHotKeyHealthMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.observePotentialRegionHotKey(event)
            return event
        }
    }

    private func configureResetMonitor() {
        globalResetMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard ExitShortcut.matches(event), NSApp.isActive else { return }
            DispatchQueue.main.async {
                self?.resetStatus()
            }
        }

        localResetMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard ExitShortcut.matches(event) else { return event }
            self?.resetStatus()
            return nil
        }
    }

    private func resetStatus() {
        statusTipPopover?.close()
        statusTipPopover = nil

        if let modalWindow = NSApp.modalWindow {
            modalWindow.close()
            return
        }

        if let controller = selectionController {
            selectionController = nil
            controller.cancel()
            return
        }

        if let keyWindow = NSApp.keyWindow {
            if let controller = editorWindows.first(where: { $0.window === keyWindow }) {
                controller.closeForExit()
                return
            }

            if let controller = settingsWindowController, controller.window === keyWindow {
                closeSettingsWindow()
                return
            }

            keyWindow.close()
            return
        }

        if let controller = editorWindows.last {
            controller.closeForExit()
            return
        }

        closeSettingsWindow()
    }

    private func closeAllTransientContexts() {
        statusTipPopover?.close()
        statusTipPopover = nil

        if let controller = selectionController {
            selectionController = nil
            controller.cancel()
        }

        closeSettingsWindow()

        let windows = editorWindows
        editorWindows.removeAll()
        windows.forEach { $0.closeForExit() }
    }

    private func closeSettingsWindow() {
        guard let controller = settingsWindowController else { return }
        settingsWindowController = nil
        controller.close()
    }

    private func observePotentialRegionHotKey(_ event: NSEvent) {
        guard let shortcut = registeredRegionShortcut, shortcut.matches(event: event) else { return }

        let observedAt = Date()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
            self?.verifyObservedRegionHotKey(shortcut, observedAt: observedAt)
        }
    }

    private func verifyObservedRegionHotKey(_ shortcut: KeyboardShortcut, observedAt: Date) {
        guard registeredRegionShortcut == shortcut, !isRecoveringRegionHotKey else { return }

        let recentSuccessfulFireCutoff = observedAt.addingTimeInterval(-0.25)
        if lastRegionHotKeyFireDate < recentSuccessfulFireCutoff {
            recoverUnresponsiveRegionHotKey(shortcut)
        }
    }

    private func recoverUnresponsiveRegionHotKey(_ shortcut: KeyboardShortcut) {
        guard !isRecoveringRegionHotKey else { return }

        isRecoveringRegionHotKey = true
        unresponsiveRegionShortcuts.insert(shortcut)
        var failedResults: [(KeyboardShortcut, HotKeyRegistrationResult)] = [(shortcut, .unresponsive)]

        let candidates = KeyboardShortcut.fallbackRegionShortcuts.filter {
            !unresponsiveRegionShortcuts.contains($0)
        }

        for candidate in candidates {
            let result = hotKeyManager.updateRegionShortcut(candidate)
            if result.isRegistered {
                AppSettings.shared.regionShortcut = candidate
                registeredRegionShortcut = candidate
                updateStatusMetadata()
                isRecoveringRegionHotKey = false
                showHotKeyChangedTip(from: shortcut, to: candidate)
                return
            }

            failedResults.append((candidate, result))
        }

        registeredRegionShortcut = nil
        updateStatusMetadata()
        isRecoveringRegionHotKey = false
        showNoAvailableShortcutTip(failedResults: failedResults)
    }

    private func handleRegionHotKey() {
        lastRegionHotKeyFireDate = Date()
        captureRegion()
    }

    @objc private func captureRegion() {
        guard ensureScreenAccess() else { return }

        let controller = ScreenSelectionController()
        selectionController = controller
        controller.start { [weak self] result in
            guard let self else { return }
            self.selectionController = nil

            guard let result else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.16) {
                let image: NSImage?
                switch result {
                case .region(let region):
                    guard region.isCapturable else { return }
                    image = self.captureService.capture(region: region)
                case .window(let target):
                    image = self.captureService.capture(windowID: target.windowID, fallbackRect: target.appKitBounds)
                case .fullScreen:
                    image = self.captureService.captureFullScreen()
                }

                if let image {
                    self.openEditor(with: image)
                } else {
                    self.showCaptureError()
                }
            }
        }
    }

    @objc private func captureFullScreen() {
        guard ensureScreenAccess() else { return }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
            if let image = self.captureService.captureFullScreen() {
                self.openEditor(with: image)
            } else {
                self.showCaptureError()
            }
        }
    }

    @objc private func openAutoSaveFolder() {
        NSWorkspace.shared.open(AutoSaveStore.saveDirectory)
    }

    @objc private func openSettings() {
        let controller = settingsWindowController ?? SettingsWindowController()
        controller.onShortcutRecordingBegan = { [weak self] in
            self?.beginRegionShortcutRecording()
        }
        controller.onShortcutRecordingCancelled = { [weak self] in
            self?.cancelRegionShortcutRecording()
        }
        controller.onShortcutChanged = { [weak self] shortcut in
            self?.applyRegionShortcut(shortcut) ?? false
        }
        controller.onSettingsChanged = { [weak self] in
            self?.applyLanguage()
            self?.updateStatusMetadata()
        }
        controller.onClose = { [weak self, weak controller] in
            guard
                let self,
                let controller,
                self.settingsWindowController === controller
            else { return }
            self.settingsWindowController = nil
        }
        settingsWindowController = controller
        controller.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func showAbout() {
        let alert = NSAlert()
        alert.messageText = "SnapMark"
        alert.informativeText = L10n.format(
            .aboutInformativeTextFormat,
            AppVersion.aboutVersionText,
            L10n.text(.aboutAppDescription),
            Self.authorContactEmail
        )
        alert.alertStyle = .informational
        alert.addButton(withTitle: L10n.text(.ok))
        alert.addButton(withTitle: L10n.text(.contactAuthor))
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertSecondButtonReturn {
            openAuthorMail()
        }
    }

    private func openAuthorMail() {
        guard let url = URL(string: "mailto:\(Self.authorContactEmail)") else { return }
        NSWorkspace.shared.open(url)
    }

    @objc private func quit() {
        NSApplication.shared.terminate(nil)
    }

    private func beginRegionShortcutRecording() -> KeyboardShortcut? {
        guard !isRecordingRegionShortcut else {
            return recordingPreviousRegionShortcut ?? registeredRegionShortcut ?? AppSettings.shared.regionShortcut
        }

        isRecordingRegionShortcut = true
        recordingPreviousRegionShortcut = registeredRegionShortcut
        hotKeyManager.unregisterRegionShortcut()
        registeredRegionShortcut = nil
        updateStatusMetadata()
        return recordingPreviousRegionShortcut ?? AppSettings.shared.regionShortcut
    }

    private func cancelRegionShortcutRecording() -> KeyboardShortcut? {
        guard isRecordingRegionShortcut else {
            return registeredRegionShortcut
        }

        let restoredShortcut = restoreRegionShortcut(recordingPreviousRegionShortcut, showError: true)
        finishRegionShortcutRecording()
        return restoredShortcut
    }

    private func applyRegionShortcut(_ shortcut: KeyboardShortcut) -> Bool {
        let previousShortcut = isRecordingRegionShortcut ? recordingPreviousRegionShortcut : registeredRegionShortcut

        let result = hotKeyManager.updateRegionShortcut(shortcut)
        guard result.isRegistered else {
            _ = restoreRegionShortcut(previousShortcut, showError: true)
            finishRegionShortcutRecording()
            showShortcutError(shortcut, result: result)
            return false
        }

        AppSettings.shared.regionShortcut = shortcut
        registeredRegionShortcut = shortcut
        unresponsiveRegionShortcuts.remove(shortcut)
        finishRegionShortcutRecording()
        updateStatusMetadata()
        return true
    }

    private func restoreRegionShortcut(_ shortcut: KeyboardShortcut?, showError: Bool) -> KeyboardShortcut? {
        guard let shortcut else {
            hotKeyManager.unregisterRegionShortcut()
            registeredRegionShortcut = nil
            updateStatusMetadata()
            return nil
        }

        let result = hotKeyManager.updateRegionShortcut(shortcut)
        if result.isRegistered {
            registeredRegionShortcut = shortcut
        } else {
            registeredRegionShortcut = nil
            if showError {
                showShortcutRestoreError(shortcut, result: result)
            }
        }

        updateStatusMetadata()
        return registeredRegionShortcut
    }

    private func finishRegionShortcutRecording() {
        isRecordingRegionShortcut = false
        recordingPreviousRegionShortcut = nil
    }

    private func updateStatusMetadata() {
        regionMenuItem?.title = L10n.text(.menuRegionCapture)
        fullScreenMenuItem?.title = L10n.text(.menuFullScreenCapture)
        openFolderMenuItem?.title = L10n.text(.menuOpenAutoSaveFolder)
        quitMenuItem?.title = L10n.text(.menuQuit)
        if let shortcut = registeredRegionShortcut {
            statusItem?.button?.toolTip = statusToolTip(hotKey: shortcut.displayString)
            settingsMenuItem?.title = "\(L10n.text(.menuSettings)) \(shortcut.shortDisplayString)"
            regionMenuItem?.keyEquivalent = shortcut.keyEquivalent
            regionMenuItem?.keyEquivalentModifierMask = shortcut.modifierFlags
        } else {
            statusItem?.button?.toolTip = statusToolTip(hotKey: L10n.text(.hotKeyUnset))
            settingsMenuItem?.title = L10n.text(.menuSettings)
            regionMenuItem?.keyEquivalent = ""
            regionMenuItem?.keyEquivalentModifierMask = []
        }
        aboutMenuItem?.title = L10n.format(.menuAboutFormat, AppVersion.aboutVersionText)
    }

    private func statusToolTip(hotKey: String) -> String {
        L10n.format(.statusToolTipFormat, AppVersion.displayVersion, hotKey)
    }

    private func applyLanguage() {
        updateStatusMetadata()
        settingsWindowController?.applyLanguage()
        editorWindows.forEach { $0.applyLanguage() }
    }

    private func ensureScreenAccess() -> Bool {
        if captureService.hasScreenCaptureAccess {
            return true
        }

        if captureService.requestScreenCaptureAccess() {
            return true
        }

        let alert = NSAlert()
        alert.messageText = L10n.text(.screenAccessTitle)
        alert.informativeText = L10n.text(.screenAccessMessage)
        alert.alertStyle = .warning
        alert.addButton(withTitle: L10n.text(.openSystemSettings))
        alert.addButton(withTitle: L10n.text(.later))
        if alert.runModal() == .alertFirstButtonReturn {
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
                NSWorkspace.shared.open(url)
            }
        }
        return false
    }

    private func openEditor(with image: NSImage) {
        let controller = EditorWindowController(image: image)
        controller.onClose = { [weak self, weak controller] in
            guard let controller else { return }
            self?.editorWindows.removeAll { $0 === controller }
        }

        editorWindows.append(controller)
        controller.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func showCaptureError() {
        let alert = NSAlert()
        alert.messageText = L10n.text(.captureErrorTitle)
        alert.informativeText = L10n.text(.captureErrorMessage)
        alert.alertStyle = .warning
        alert.runModal()
    }

    private func showShortcutError(_ shortcut: KeyboardShortcut, result: HotKeyRegistrationResult) {
        let alert = NSAlert()
        alert.messageText = L10n.text(.shortcutSetErrorTitle)
        alert.informativeText = hotKeyFailureMessage(for: shortcut, result: result) + "\n" + L10n.text(.shortcutRetryMessage)
        alert.alertStyle = .warning
        alert.runModal()
    }

    private func showShortcutRestoreError(_ shortcut: KeyboardShortcut, result: HotKeyRegistrationResult) {
        let alert = NSAlert()
        alert.messageText = L10n.text(.shortcutRestoreErrorTitle)
        alert.informativeText = hotKeyFailureMessage(for: shortcut, result: result) + "\n" + L10n.text(.shortcutRetryMessage)
        alert.alertStyle = .warning
        alert.runModal()
    }

    private func showStartupShortcutConflict(_ shortcut: KeyboardShortcut, result: HotKeyRegistrationResult) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
            guard let self else { return }
            let alert = NSAlert()
            alert.messageText = L10n.text(.shortcutUnavailableTitle)
            alert.informativeText = self.hotKeyFailureMessage(for: shortcut, result: result) + "\n" + L10n.text(.shortcutResetMessage)
            alert.alertStyle = .warning
            alert.addButton(withTitle: L10n.text(.openSettings))
            alert.addButton(withTitle: L10n.text(.later))
            NSApp.activate(ignoringOtherApps: true)
            if alert.runModal() == .alertFirstButtonReturn {
                self.openSettings()
            }
        }
    }

    private func showStartupFallbackNotice(failedResults: [(KeyboardShortcut, HotKeyRegistrationResult)], activeShortcut: KeyboardShortcut) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
            guard let self else { return }
            let failedMessages = failedResults
                .map { self.hotKeyFailureMessage(for: $0.0, result: $0.1) }
                .joined(separator: "\n")

            let alert = NSAlert()
            alert.messageText = L10n.text(.shortcutFallbackTitle)
            alert.informativeText = L10n.format(.shortcutFallbackMessageFormat, failedMessages, activeShortcut.displayString)
            alert.alertStyle = .informational
            alert.addButton(withTitle: L10n.text(.ok))
            alert.addButton(withTitle: L10n.text(.openSettings))
            NSApp.activate(ignoringOtherApps: true)
            if alert.runModal() == .alertSecondButtonReturn {
                self.openSettings()
            }
        }
    }

    private func showNoAvailableShortcutTip(failedResults: [(KeyboardShortcut, HotKeyRegistrationResult)]) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
            guard let self else { return }
            let failedMessages = failedResults
                .map { self.hotKeyFailureMessage(for: $0.0, result: $0.1) }
                .joined(separator: "\n")

            let alert = NSAlert()
            alert.messageText = L10n.text(.shortcutRequiredTitle)
            alert.informativeText = "\(failedMessages)\n\(L10n.text(.shortcutResetMessage))"
            alert.alertStyle = .warning
            alert.addButton(withTitle: L10n.text(.openSettings))
            alert.addButton(withTitle: L10n.text(.later))
            NSApp.activate(ignoringOtherApps: true)
            if alert.runModal() == .alertFirstButtonReturn {
                self.openSettings()
            }
        }
    }

    private func hotKeyFailureMessage(for shortcut: KeyboardShortcut, result: HotKeyRegistrationResult) -> String {
        if result.isOccupied {
            return L10n.format(.shortcutOccupiedFormat, shortcut.displayString)
        }

        if result == .unresponsive {
            return L10n.format(.shortcutUnresponsiveFormat, shortcut.displayString)
        }

        if let status = result.status {
            return L10n.format(.shortcutStatusFailureFormat, shortcut.displayString, status)
        }

        return L10n.format(.shortcutFailureFormat, shortcut.displayString)
    }

    private func showHotKeyChangedTip(from oldShortcut: KeyboardShortcut, to newShortcut: KeyboardShortcut) {
        let message = L10n.format(.shortcutChangedTipFormat, oldShortcut.displayString, newShortcut.displayString)
        showStatusTip(message)
    }

    private func showStatusTip(_ message: String) {
        guard let button = statusItem?.button else { return }

        statusTipPopover?.close()

        let label = NSTextField(labelWithString: message)
        label.font = .systemFont(ofSize: 13, weight: .medium)
        label.textColor = .labelColor
        label.maximumNumberOfLines = 0
        label.lineBreakMode = .byWordWrapping
        label.translatesAutoresizingMaskIntoConstraints = false

        let view = NSView(frame: CGRect(x: 0, y: 0, width: 300, height: 92))
        view.addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 14),
            label.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -14),
            label.topAnchor.constraint(equalTo: view.topAnchor, constant: 12),
            label.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -12)
        ])

        let viewController = NSViewController()
        viewController.view = view

        let popover = NSPopover()
        popover.behavior = .transient
        popover.contentSize = view.frame.size
        popover.contentViewController = viewController
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)

        statusTipPopover = popover
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self, weak popover] in
            popover?.close()
            if self?.statusTipPopover === popover {
                self?.statusTipPopover = nil
            }
        }
    }
}
