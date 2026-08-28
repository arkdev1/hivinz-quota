import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {

    private let notch = NotchController()
    private var appearanceObservation: NSKeyValueObservation?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Accessory app: no Dock icon, no main window.
        NSApp.setActivationPolicy(.accessory)
        UsageStore.shared.start()
        notch.start()

        // Under the "system" theme the widget follows macOS light/dark; this is
        // the signal that tells the views to repaint when that flips.
        appearanceObservation = NSApp.observe(\.effectiveAppearance) { _, _ in
            Task { @MainActor in Preferences.shared.appearanceTick += 1 }
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}
