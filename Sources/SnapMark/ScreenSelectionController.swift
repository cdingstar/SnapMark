import AppKit
import CoreGraphics

enum ScreenSelectionResult {
    case region(ScreenCaptureRegion)
    case window(WindowTarget)
    case fullScreen
}

final class ScreenSelectionController {
    private var windows: [NSWindow] = []
    private var completion: ((ScreenSelectionResult?) -> Void)?
    private var isFinishing = false

    func start(completion: @escaping (ScreenSelectionResult?) -> Void) {
        self.completion = completion
        isFinishing = false

        let windowTargets = WindowInspector.visibleWindowTargets()

        windows = NSScreen.screens.map { screen in
            let window = makeOverlayWindow(for: screen)
            let view = ScreenSelectionView(
                frame: CGRect(origin: .zero, size: screen.frame.size),
                screenSnapshot: screenSnapshot(for: screen),
                windowTargets: windowTargets
            )
            bind(view, to: window)
            window.contentView = view
            return window
        }

        NSApp.activate(ignoringOtherApps: true)
        windows.forEach { window in
            window.makeKeyAndOrderFront(nil)
            window.makeFirstResponder(window.contentView)
        }
    }

    func cancel() {
        finish(nil)
    }

    private func makeOverlayWindow(for screen: NSScreen) -> NSWindow {
        let window = ScreenSelectionWindow(
            contentRect: screen.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false,
            screen: screen
        )
        window.isOpaque = false
        window.backgroundColor = .clear
        window.level = .screenSaver
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        window.ignoresMouseEvents = false
        window.acceptsMouseMovedEvents = true
        window.hasShadow = false
        window.animationBehavior = .none
        window.isReleasedWhenClosed = false
        return window
    }

    private func screenSnapshot(for screen: NSScreen) -> CGImage? {
        CGWindowListCreateImage(
            ScreenCaptureRegion.coreGraphicsDisplayBounds(for: screen).integral,
            .optionOnScreenOnly,
            kCGNullWindowID,
            [.bestResolution]
        )
    }

    private func bind(_ view: ScreenSelectionView, to window: NSWindow) {
        view.onRegionComplete = { [weak self, weak window] localRect in
            guard let window else {
                self?.finish(nil)
                return
            }
            let screenRect = window.convertToScreen(localRect)
            guard let region = ScreenCaptureRegion(appKitRect: screenRect, screen: window.screen) else {
                self?.finish(nil)
                return
            }
            self?.finish(.region(region))
        }
        view.onWindowComplete = { [weak self] target in
            self?.finish(.window(target))
        }
        view.onFullScreenComplete = { [weak self] in
            self?.finish(.fullScreen)
        }
        view.onCancel = { [weak self] in
            self?.finish(nil)
        }
    }

    private func finish(_ result: ScreenSelectionResult?) {
        guard !isFinishing else { return }
        isFinishing = true

        let closingWindows = windows
        let completion = completion
        windows.removeAll()
        self.completion = nil

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0
            context.allowsImplicitAnimation = false
            closingWindows.forEach { window in
                window.animationBehavior = .none
                window.orderOut(nil)
            }
        }

        completion?(result)

        DispatchQueue.main.async {
            closingWindows.forEach { window in
                window.contentView = nil
                window.close()
            }
        }
    }
}
