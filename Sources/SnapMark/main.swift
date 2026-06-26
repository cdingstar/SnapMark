import AppKit

UserDefaults.standard.set(180, forKey: "NSInitialToolTipDelay")

let app = NSApplication.shared
let delegate = AppDelegate()

app.delegate = delegate
app.setActivationPolicy(.accessory)
ProcessInfo.processInfo.disableAutomaticTermination("SnapMark stays available from the menu bar between captures.")
app.run()
