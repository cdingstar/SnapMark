import AppKit
import Carbon.HIToolbox

final class AppSettings {
    static let shared = AppSettings()

    private let defaults = UserDefaults.standard

    private enum Key {
        static let shortcutKeyCode = "regionShortcut.keyCode"
        static let shortcutModifiers = "regionShortcut.modifiers"
        static let shortcutEquivalent = "regionShortcut.keyEquivalent"
        static let shortcutDisplayKey = "regionShortcut.displayKey"
        static let saveDirectory = "saveDirectory"
    }

    private init() {}

    var hasStoredRegionShortcut: Bool {
        defaults.object(forKey: Key.shortcutKeyCode) != nil
    }

    var regionShortcut: KeyboardShortcut {
        get {
            guard defaults.object(forKey: Key.shortcutKeyCode) != nil else {
                return .defaultRegion
            }

            let keyCode = UInt32(defaults.integer(forKey: Key.shortcutKeyCode))
            let modifiers = NSEvent.ModifierFlags(rawValue: UInt(defaults.integer(forKey: Key.shortcutModifiers)))
            let keyEquivalent = defaults.string(forKey: Key.shortcutEquivalent) ?? "a"
            let displayKey = defaults.string(forKey: Key.shortcutDisplayKey) ?? "A"

            return KeyboardShortcut(
                keyCode: keyCode,
                modifierFlags: modifiers,
                keyEquivalent: keyEquivalent,
                displayKey: displayKey
            )
        }
        set {
            defaults.set(Int(newValue.keyCode), forKey: Key.shortcutKeyCode)
            defaults.set(Int(newValue.modifierFlags.rawValue), forKey: Key.shortcutModifiers)
            defaults.set(newValue.keyEquivalent, forKey: Key.shortcutEquivalent)
            defaults.set(newValue.displayKey, forKey: Key.shortcutDisplayKey)
        }
    }

    var saveDirectory: URL {
        get {
            if let path = defaults.string(forKey: Key.saveDirectory), !path.isEmpty {
                return URL(fileURLWithPath: path, isDirectory: true)
            }

            return FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
                ?? FileManager.default.homeDirectoryForCurrentUser
        }
        set {
            defaults.set(newValue.path, forKey: Key.saveDirectory)
        }
    }
}

struct KeyboardShortcut: Equatable, Hashable {
    var keyCode: UInt32
    var modifierFlags: NSEvent.ModifierFlags
    var keyEquivalent: String
    var displayKey: String

    func hash(into hasher: inout Hasher) {
        hasher.combine(keyCode)
        hasher.combine(modifierFlags.rawValue)
        hasher.combine(keyEquivalent)
        hasher.combine(displayKey)
    }

    static let defaultRegion = KeyboardShortcut(
        keyCode: UInt32(kVK_ANSI_A),
        modifierFlags: [.command, .control],
        keyEquivalent: "a",
        displayKey: "A"
    )

    static let fallbackRegionShortcuts = [
        KeyboardShortcut(
            keyCode: UInt32(kVK_ANSI_A),
            modifierFlags: [.command, .control],
            keyEquivalent: "a",
            displayKey: "A"
        ),
        KeyboardShortcut(
            keyCode: UInt32(kVK_ANSI_S),
            modifierFlags: [.command, .control],
            keyEquivalent: "s",
            displayKey: "S"
        ),
        KeyboardShortcut(
            keyCode: UInt32(kVK_ANSI_Q),
            modifierFlags: [.command, .control],
            keyEquivalent: "q",
            displayKey: "Q"
        )
    ]

    var isFallbackCandidate: Bool {
        KeyboardShortcut.fallbackRegionShortcuts.contains(self)
    }

    var displayString: String {
        var parts: [String] = []
        if modifierFlags.contains(.command) {
            parts.append("Command")
        }
        if modifierFlags.contains(.control) {
            parts.append("Control")
        }
        if modifierFlags.contains(.option) {
            parts.append("Option")
        }
        if modifierFlags.contains(.shift) {
            parts.append("Shift")
        }
        parts.append(displayKey)
        return parts.joined(separator: "+")
    }

    var shortDisplayString: String {
        var result = ""
        if modifierFlags.contains(.control) {
            result += "^"
        }
        if modifierFlags.contains(.option) {
            result += "⌥"
        }
        if modifierFlags.contains(.shift) {
            result += "⇧"
        }
        if modifierFlags.contains(.command) {
            result += "⌘"
        }
        result += displayKey
        return result
    }

    func matches(event: NSEvent) -> Bool {
        let modifiers = event.modifierFlags.intersection([.command, .control, .option, .shift])
        return UInt32(event.keyCode) == keyCode && modifiers == modifierFlags
    }

    var carbonModifiers: UInt32 {
        var modifiers: UInt32 = 0
        if modifierFlags.contains(.command) {
            modifiers |= UInt32(cmdKey)
        }
        if modifierFlags.contains(.control) {
            modifiers |= UInt32(controlKey)
        }
        if modifierFlags.contains(.option) {
            modifiers |= UInt32(optionKey)
        }
        if modifierFlags.contains(.shift) {
            modifiers |= UInt32(shiftKey)
        }
        return modifiers
    }

    static func from(event: NSEvent) -> KeyboardShortcut? {
        let modifiers = event.modifierFlags.intersection([.command, .control, .option, .shift])
        guard !modifiers.isEmpty, !modifierOnlyKeyCodes.contains(Int(event.keyCode)) else {
            return nil
        }

        let equivalent = KeyCodeFormatter.keyEquivalent(for: event)
        guard !equivalent.isEmpty else {
            return nil
        }

        return KeyboardShortcut(
            keyCode: UInt32(event.keyCode),
            modifierFlags: modifiers,
            keyEquivalent: equivalent,
            displayKey: KeyCodeFormatter.displayKey(for: event, keyEquivalent: equivalent)
        )
    }

    private static let modifierOnlyKeyCodes: Set<Int> = [
        kVK_Command,
        kVK_RightCommand,
        kVK_Control,
        kVK_RightControl,
        kVK_Option,
        kVK_RightOption,
        kVK_Shift,
        kVK_RightShift,
        kVK_CapsLock,
        kVK_Function
    ]
}

private enum KeyCodeFormatter {
    static func keyEquivalent(for event: NSEvent) -> String {
        if let characters = event.charactersIgnoringModifiers, let first = characters.first {
            return String(first).lowercased()
        }

        return specialKeyEquivalent[Int(event.keyCode)] ?? ""
    }

    static func displayKey(for event: NSEvent, keyEquivalent: String) -> String {
        if let display = specialDisplayName[Int(event.keyCode)] {
            return display
        }

        return keyEquivalent.uppercased()
    }

    private static let specialKeyEquivalent: [Int: String] = [
        kVK_Return: "\r",
        kVK_Tab: "\t",
        kVK_Space: " ",
        kVK_Delete: "\u{8}",
        kVK_Escape: "\u{1b}",
        kVK_F1: NSF1FunctionKey.unicodeScalarString,
        kVK_F2: NSF2FunctionKey.unicodeScalarString,
        kVK_F3: NSF3FunctionKey.unicodeScalarString,
        kVK_F4: NSF4FunctionKey.unicodeScalarString,
        kVK_F5: NSF5FunctionKey.unicodeScalarString,
        kVK_F6: NSF6FunctionKey.unicodeScalarString,
        kVK_F7: NSF7FunctionKey.unicodeScalarString,
        kVK_F8: NSF8FunctionKey.unicodeScalarString,
        kVK_F9: NSF9FunctionKey.unicodeScalarString,
        kVK_F10: NSF10FunctionKey.unicodeScalarString,
        kVK_F11: NSF11FunctionKey.unicodeScalarString,
        kVK_F12: NSF12FunctionKey.unicodeScalarString
    ]

    private static let specialDisplayName: [Int: String] = [
        kVK_Return: "Return",
        kVK_Tab: "Tab",
        kVK_Space: "Space",
        kVK_Delete: "Delete",
        kVK_Escape: "Esc",
        kVK_F1: "F1",
        kVK_F2: "F2",
        kVK_F3: "F3",
        kVK_F4: "F4",
        kVK_F5: "F5",
        kVK_F6: "F6",
        kVK_F7: "F7",
        kVK_F8: "F8",
        kVK_F9: "F9",
        kVK_F10: "F10",
        kVK_F11: "F11",
        kVK_F12: "F12"
    ]
}

private extension Int {
    var unicodeScalarString: String {
        guard let scalar = UnicodeScalar(self) else { return "" }
        return String(Character(scalar))
    }
}
