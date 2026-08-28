import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {

    private let notch = NotchController()

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Accessory app: no Dock icon, no main window.
        NSApp.setActivationPolicy(.accessory)
        UsageStore.shared.start()
        notch.start()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}
