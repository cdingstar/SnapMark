import AppKit
import Carbon.HIToolbox

enum HotKeyRegistrationResult: Equatable {
    case registered
    case failed(OSStatus)
    case unresponsive

    var isRegistered: Bool {
        self == .registered
    }

    var status: OSStatus? {
        switch self {
        case .registered:
            return nil
        case .failed(let status):
            return status
        case .unresponsive:
            return nil
        }
    }

    var isOccupied: Bool {
        guard let status else { return false }
        return status == eventHotKeyExistsErr
    }
}

final class HotKeyManager {
    typealias Handler = () -> Void

    private static let signature: OSType = {
        var result: UInt32 = 0
        for scalar in "SNPM".unicodeScalars {
            result = (result << 8) + scalar.value
        }
        return OSType(result)
    }()

    private var hotKeyRefs: [EventHotKeyRef?] = []
    private var eventHandler: EventHandlerRef?
    private var handlers: [UInt32: Handler] = [:]

    deinit {
        hotKeyRefs.forEach { ref in
            if let ref {
                UnregisterEventHotKey(ref)
            }
        }

        if let eventHandler {
            RemoveEventHandler(eventHandler)
        }
    }

    func register(regionShortcut: KeyboardShortcut, region: @escaping Handler) -> HotKeyRegistrationResult {
        handlers = [
            1: region
        ]

        installHandlerIfNeeded()
        return updateRegionShortcut(regionShortcut)
    }

    func updateRegionShortcut(_ shortcut: KeyboardShortcut) -> HotKeyRegistrationResult {
        unregisterHotKeys()
        let status = registerHotKey(id: 1, shortcut: shortcut)
        return status == noErr ? .registered : .failed(status)
    }

    private func installHandlerIfNeeded() {
        guard eventHandler == nil else { return }

        var eventSpec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let selfPointer = Unmanaged.passUnretained(self).toOpaque()

        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, eventRef, userData in
                guard let eventRef, let userData else { return noErr }

                var hotKeyID = EventHotKeyID()
                let status = GetEventParameter(
                    eventRef,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &hotKeyID
                )

                guard status == noErr else { return status }

                let manager = Unmanaged<HotKeyManager>.fromOpaque(userData).takeUnretainedValue()
                DispatchQueue.main.async {
                    manager.handlers[hotKeyID.id]?()
                }

                return noErr
            },
            1,
            &eventSpec,
            selfPointer,
            &eventHandler
        )
    }

    private func unregisterHotKeys() {
        hotKeyRefs.forEach { ref in
            if let ref {
                UnregisterEventHotKey(ref)
            }
        }
        hotKeyRefs.removeAll()
    }

    private func registerHotKey(id: UInt32, shortcut: KeyboardShortcut) -> OSStatus {
        let hotKeyID = EventHotKeyID(signature: HotKeyManager.signature, id: id)
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(
            shortcut.keyCode,
            shortcut.carbonModifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &ref
        )

        if status == noErr {
            hotKeyRefs.append(ref)
        }

        return status
    }
}
