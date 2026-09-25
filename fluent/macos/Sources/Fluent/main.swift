import AppKit

// Initialize the application object before calling any NSApp methods.
let app = NSApplication.shared
app.setActivationPolicy(.accessory)

let delegate = AppDelegate()
app.delegate = delegate
app.run()
