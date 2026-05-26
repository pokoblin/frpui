import AppKit
import SwiftUI

/// Manages the settings window via AppKit so it can be reliably brought to the front
/// and activated on every invocation — including when it already exists behind another
/// app's window. (An LSUIElement app does not auto-activate, and SettingsLink offers no
/// per-click hook.)
final class SettingsWindowController {
    static let shared = SettingsWindowController()

    private var window: NSWindow?

    func show() {
        if window == nil {
            let hosting = NSHostingController(
                rootView: SettingsView().environmentObject(AppState.shared))
            hosting.sizingOptions = [.preferredContentSize]

            let win = NSWindow(contentViewController: hosting)
            win.title = "Settings"
            win.styleMask = [.titled, .closable, .miniaturizable]
            win.isReleasedWhenClosed = false
            win.center()
            window = win
        }

        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}
