import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let captureService = ScreenCaptureService()
    private let hotKeyManager = HotKeyManager()
    private var statusItem: NSStatusItem?
    private var regionMenuItem: NSMenuItem?
    private var settingsMenuItem: NSMenuItem?
    private var registeredRegionShortcut: KeyboardShortcut?
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
        let regionItem = NSMenuItem(title: "区域截图", action: #selector(captureRegion), keyEquivalent: "")
        regionMenuItem = regionItem
        menu.addItem(regionItem)

        menu.addItem(NSMenuItem(title: "全屏截图", action: #selector(captureFullScreen), keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "打开自动保存文件夹", action: #selector(openAutoSaveFolder), keyEquivalent: "o"))
        let settingsItem = NSMenuItem(title: "设置...", action: #selector(openSettings), keyEquivalent: "")
        settingsMenuItem = settingsItem
        menu.addItem(settingsItem)
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "退出", action: #selector(quit), keyEquivalent: "q"))

        menu.items.forEach { $0.target = self }
        item.menu = menu
        statusItem = item
        updateStatusMetadata()
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
            guard event.keyCode == 53 else { return }
            DispatchQueue.main.async {
                self?.resetStatus()
            }
        }

        localResetMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard event.keyCode == 53 else { return event }
            self?.resetStatus()
            return nil
        }
    }

    private func resetStatus() {
        statusTipPopover?.close()
        statusTipPopover = nil

        selectionController?.cancel()
        selectionController = nil

        settingsWindowController?.close()
        editorWindows.forEach { $0.resetAndClose() }
        editorWindows.removeAll()
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
                case .region(let rect):
                    guard rect.width >= 4, rect.height >= 4 else { return }
                    image = self.captureService.capture(rect: rect)
                case .window(let target):
                    image = self.captureService.capture(windowID: target.windowID, fallbackRect: target.appKitBounds)
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
        controller.onShortcutChanged = { [weak self] shortcut in
            self?.applyRegionShortcut(shortcut) ?? false
        }
        controller.onSettingsChanged = { [weak self] in
            self?.updateStatusMetadata()
        }
        settingsWindowController = controller
        controller.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func quit() {
        NSApplication.shared.terminate(nil)
    }

    private func applyRegionShortcut(_ shortcut: KeyboardShortcut) -> Bool {
        let previousShortcut = registeredRegionShortcut

        let result = hotKeyManager.updateRegionShortcut(shortcut)
        guard result.isRegistered else {
            if let previousShortcut {
                let restoreResult = hotKeyManager.updateRegionShortcut(previousShortcut)
                registeredRegionShortcut = restoreResult.isRegistered ? previousShortcut : nil
            } else {
                registeredRegionShortcut = nil
            }
            updateStatusMetadata()
            showShortcutError(shortcut, result: result)
            return false
        }

        AppSettings.shared.regionShortcut = shortcut
        registeredRegionShortcut = shortcut
        unresponsiveRegionShortcuts.remove(shortcut)
        updateStatusMetadata()
        return true
    }

    private func updateStatusMetadata() {
        if let shortcut = registeredRegionShortcut {
            statusItem?.button?.toolTip = statusToolTip(hotKey: shortcut.displayString)
            settingsMenuItem?.title = "设置... \(shortcut.shortDisplayString)"
            regionMenuItem?.keyEquivalent = shortcut.keyEquivalent
            regionMenuItem?.keyEquivalentModifierMask = shortcut.modifierFlags
        } else {
            statusItem?.button?.toolTip = statusToolTip(hotKey: "未设置")
            settingsMenuItem?.title = "设置..."
            regionMenuItem?.keyEquivalent = ""
            regionMenuItem?.keyEquivalentModifierMask = []
        }
    }

    private func statusToolTip(hotKey: String) -> String {
        "SnapMark V\(AppVersion.displayVersion)\n\n快捷键 \(hotKey)\n\nmailto: cdingstar@gmail.com"
    }

    private func ensureScreenAccess() -> Bool {
        if captureService.hasScreenCaptureAccess {
            return true
        }

        if captureService.requestScreenCaptureAccess() {
            return true
        }

        let alert = NSAlert()
        alert.messageText = "需要屏幕录制权限"
        alert.informativeText = "请在 系统设置 > 隐私与安全性 > 屏幕录制 中允许 SnapMark，然后重新截图。"
        alert.alertStyle = .warning
        alert.addButton(withTitle: "打开系统设置")
        alert.addButton(withTitle: "稍后")
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
        alert.messageText = "截图失败"
        alert.informativeText = "没有拿到屏幕图像，请确认屏幕录制权限已开启。"
        alert.alertStyle = .warning
        alert.runModal()
    }

    private func showShortcutError(_ shortcut: KeyboardShortcut, result: HotKeyRegistrationResult) {
        let alert = NSAlert()
        alert.messageText = "快捷键设置失败"
        alert.informativeText = hotKeyFailureMessage(for: shortcut, result: result) + "\n请重新选择 Hotkey。"
        alert.alertStyle = .warning
        alert.runModal()
    }

    private func showStartupShortcutConflict(_ shortcut: KeyboardShortcut, result: HotKeyRegistrationResult) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
            guard let self else { return }
            let alert = NSAlert()
            alert.messageText = "截图快捷键不可用"
            alert.informativeText = self.hotKeyFailureMessage(for: shortcut, result: result) + "\n请在设置中重新选择 Hotkey。"
            alert.alertStyle = .warning
            alert.addButton(withTitle: "打开设置")
            alert.addButton(withTitle: "稍后")
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
            alert.messageText = "截图快捷键已自动调整"
            alert.informativeText = "\(failedMessages)\n已自动改用 \(activeShortcut.displayString)。"
            alert.alertStyle = .informational
            alert.addButton(withTitle: "知道了")
            alert.addButton(withTitle: "打开设置")
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
            alert.messageText = "需要设置截图快捷键"
            alert.informativeText = "\(failedMessages)\n默认快捷键都不可用，请在设置中重新选择 Hotkey。"
            alert.alertStyle = .warning
            alert.addButton(withTitle: "打开设置")
            alert.addButton(withTitle: "稍后")
            NSApp.activate(ignoringOtherApps: true)
            if alert.runModal() == .alertFirstButtonReturn {
                self.openSettings()
            }
        }
    }

    private func hotKeyFailureMessage(for shortcut: KeyboardShortcut, result: HotKeyRegistrationResult) -> String {
        if result.isOccupied {
            return "\(shortcut.displayString) 已被其他应用程序或系统注册。macOS 未提供具体应用名称。"
        }

        if result == .unresponsive {
            return "\(shortcut.displayString) 注册成功但按下后没有触发 SnapMark，可能被其他应用拦截。"
        }

        if let status = result.status {
            return "\(shortcut.displayString) 注册失败（OSStatus \(status)）。"
        }

        return "\(shortcut.displayString) 注册失败。"
    }

    private func showHotKeyChangedTip(from oldShortcut: KeyboardShortcut, to newShortcut: KeyboardShortcut) {
        let message = "快捷键已自动切换\n\n\(oldShortcut.displayString) 没有触发 SnapMark\n已改为 \(newShortcut.displayString)"
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
