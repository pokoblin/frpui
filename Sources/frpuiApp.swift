import SwiftUI
import AppKit

@main
struct frpuiApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var appState = AppState.shared

    var body: some Scene {
        MenuBarExtra("frpui", systemImage: menuBarSymbol) {
            MenuContent()
                .environmentObject(appState)
        }
        .menuBarExtraStyle(.menu)
    }

    private var menuBarSymbol: String {
        appState.serviceState == .stopped ? "personalhotspot.slash" : "personalhotspot"
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
        Text("frpui v\(appVersion)")

        Divider()

        if appState.launchMode == .systemDaemon {
            Button(action: {}) {
                systemStatusLabel
            }
            .disabled(true)
        } else {
            Button(action: { appState.toggleRunning() }) {
                startServiceLabel
            }
        }

        Divider()

        Button("Settings…") {
            SettingsWindowController.shared.show()
        }
        .keyboardShortcut(",", modifiers: .command)

        Divider()

        Button("Quit") {
            NSApplication.shared.terminate(nil)
        }
        .keyboardShortcut("q", modifiers: .command)
    }

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
    }

    private var startServiceLabel: Text {
        let dot = Text("  ●").font(.system(size: 10))
        switch appState.serviceState {
        case .stopped: return Text("Start Service")
        case .starting: return Text("Starting Service") + dot.foregroundColor(.yellow)
        case .running: return Text("Stop Service") + dot.foregroundColor(.green)
        }
    }

    private var systemStatusLabel: Text {
        let dot = Text("  ●").font(.system(size: 10))
        switch appState.serviceState {
        case .stopped: return Text("System service: stopped")
        case .starting: return Text("System service: starting") + dot.foregroundColor(.yellow)
        case .running: return Text("System service: running") + dot.foregroundColor(.green)
        }
    }
}
