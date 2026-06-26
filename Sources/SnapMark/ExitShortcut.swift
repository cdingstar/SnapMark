import AppKit

enum ExitShortcut {
    static func matches(_ event: NSEvent) -> Bool {
        if event.keyCode == 53 {
            return true
        }

        guard event.charactersIgnoringModifiers?.lowercased() == "q" else {
            return false
        }

        var flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        flags.remove(.capsLock)
        return flags == .command
    }
}
