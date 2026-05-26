import Foundation
import ServiceManagement

enum LaunchMode: String, CaseIterable, Identifiable {
    case off
    case userLogin
    case systemDaemon

    var id: String { rawValue }

    var title: String {
        switch self {
        case .off: return "Off"
        case .userLogin: return "At login (current user)"
        case .systemDaemon: return "At startup (system, requires authorization)"
        }
    }
}

/// Wraps SMAppService registration for the three launch modes and the privileged
/// steps needed by the system daemon (config mirror + reload).
enum LaunchManager {
    static let daemonPlistName = "com.tonda.frpui.daemon.plist"
    static let daemonLabel = "com.tonda.frpui.daemon"
    static let systemConfigDir = "/Library/Application Support/frpui"
    static let systemConfigPath = "/Library/Application Support/frpui/frpc.toml"
    static let daemonLogPath = "/Library/Logs/frpui-frpc.log"

    private static var loginItem: SMAppService { .mainApp }
    private static var daemon: SMAppService { .daemon(plistName: daemonPlistName) }

    static var daemonEnabled: Bool { daemon.status == .enabled }

    /// Reconcile the registered services to match `mode`.
    /// When `mirrorConfig` is true (user-initiated switch to system mode), copy the
    /// current config to the system location, which triggers an admin prompt.
    /// Returns a user-facing message (info or error) or nil on plain success.
    static func apply(_ mode: LaunchMode, mirrorConfig: Bool) -> String? {
        switch mode {
        case .off:
            tryUnregister(loginItem)
            tryUnregister(daemon)
            return nil

        case .userLogin:
            tryUnregister(daemon)
            do {
                if loginItem.status != .enabled {
                    try loginItem.register()
                }
            } catch {
                return "Could not enable login item: \(error.localizedDescription)"
            }
            return nil

        case .systemDaemon:
            tryUnregister(loginItem)
            if mirrorConfig {
                guard mirrorConfigToSystem() else {
                    return "Authorization was cancelled or failed; the system service was not configured."
                }
            }
            do {
                if daemon.status != .enabled {
                    try daemon.register()
                }
            } catch {
                return "Could not register the system daemon: \(error.localizedDescription). A signed build (./build.sh) is required."
            }
            if daemon.status == .requiresApproval {
                SMAppService.openSystemSettingsLoginItems()
                return "Approve \"frpui\" in System Settings ▸ General ▸ Login Items to finish enabling the system service."
            }
            return nil
        }
    }

    /// Push the current config to the system location and restart the daemon (one admin prompt).
    static func pushConfigAndReload() -> Bool {
        let src = ConfigStore.configURL.path
        let cmd = "/bin/mkdir -p '\(systemConfigDir)' && /bin/cp '\(src)' '\(systemConfigPath)' && /bin/launchctl kickstart -k system/\(daemonLabel)"
        return runPrivileged(cmd)
    }

    private static func mirrorConfigToSystem() -> Bool {
        let src = ConfigStore.configURL.path
        let cmd = "/bin/mkdir -p '\(systemConfigDir)' && /bin/cp '\(src)' '\(systemConfigPath)'"
        return runPrivileged(cmd)
    }

    private static func tryUnregister(_ service: SMAppService) {
        if service.status == .enabled || service.status == .requiresApproval {
            try? service.unregister()
        }
    }

    /// Runs a shell command as root via the standard macOS authorization dialog.
    private static func runPrivileged(_ command: String) -> Bool {
        let escaped = command
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        let source = "do shell script \"\(escaped)\" with administrator privileges"
        guard let script = NSAppleScript(source: source) else { return false }
        var error: NSDictionary?
        script.executeAndReturnError(&error)
        return error == nil
    }
}
