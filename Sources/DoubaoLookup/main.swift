import Cocoa

// Entry point — sets up NSApplication and runs the event loop
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
