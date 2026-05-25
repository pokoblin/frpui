import SwiftUI
import AppKit

@main
struct frpuiApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var appState = AppState.shared

    var body: some Scene {
        MenuBarExtra("frpui", systemImage: appState.serviceState == .stopped ? "personalhotspot.slash" : "personalhotspot") {
            MenuContent()
                .environmentObject(appState)
        }
        .menuBarExtraStyle(.menu)

        Settings {
            SettingsView()
                .environmentObject(appState)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        AppState.shared.bootstrap()
    }

    func applicationWillTerminate(_ notification: Notification) {
        AppState.shared.stopService()
    }
}

struct MenuContent: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        Button(action: { appState.toggleRunning() }) {
            startServiceLabel
        }

        Divider()

        SettingsLink {
            Text("Settings…")
        }
        .keyboardShortcut(",", modifiers: .command)

        Divider()

        Button("Quit") {
            NSApplication.shared.terminate(nil)
        }
        .keyboardShortcut("q", modifiers: .command)
    }

    private var startServiceLabel: Text {
        let dot = Text("  ●").font(.system(size: 10))
        switch appState.serviceState {
        case .stopped: return Text("Start Service")
        case .starting: return Text("Starting Service") + dot.foregroundColor(.yellow)
        case .running: return Text("Stop Service") + dot.foregroundColor(.green)
        }
    }
}
