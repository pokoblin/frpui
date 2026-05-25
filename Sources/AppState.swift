import SwiftUI
import ServiceManagement

enum ServiceState {
    case stopped
    case starting
    case running
}

final class AppState: ObservableObject {
    static let shared = AppState()

    private enum Key {
        static let appearance = "appearance"
        static let autoStartService = "autoStartService"
        static let launchAtLogin = "launchAtLogin"
    }

    private let maxLogLength = 100_000
    private let successMarker = "start proxy success"

    @Published var appearance: AppAppearance {
        didSet {
            UserDefaults.standard.set(appearance.rawValue, forKey: Key.appearance)
            appearance.apply()
        }
    }

    @Published var autoStartService: Bool {
        didSet { UserDefaults.standard.set(autoStartService, forKey: Key.autoStartService) }
    }

    @Published var launchAtLogin: Bool {
        didSet {
            UserDefaults.standard.set(launchAtLogin, forKey: Key.launchAtLogin)
            applyLoginItem()
        }
    }

    @Published var serviceState: ServiceState = .stopped
    @Published var log: String = ""
    @Published var lastError: String?

    private let frpc = FRPCManager()

    var isActive: Bool { serviceState != .stopped }

    private init() {
        let defaults = UserDefaults.standard
        defaults.register(defaults: [
            Key.appearance: AppAppearance.system.rawValue,
            Key.autoStartService: false,
            Key.launchAtLogin: true,
        ])
        appearance = AppAppearance(rawValue: defaults.string(forKey: Key.appearance) ?? "") ?? .system
        autoStartService = defaults.bool(forKey: Key.autoStartService)
        launchAtLogin = defaults.bool(forKey: Key.launchAtLogin)

        frpc.onTerminate = { [weak self] in
            self?.serviceState = .stopped
        }
        frpc.onOutput = { [weak self] chunk in
            self?.appendLog(chunk)
        }
    }

    /// Apply persisted preferences at launch and optionally auto-start the service.
    func bootstrap() {
        appearance.apply()
        applyLoginItem()
        if autoStartService {
            setRunning(true)
        }
    }

    // MARK: - Service control

    func setRunning(_ running: Bool) {
        if running {
            log = ""
            serviceState = .starting
            do {
                try frpc.start()
                lastError = nil
            } catch {
                serviceState = .stopped
                lastError = error.localizedDescription
                appendLog("Failed to start frpc: \(error.localizedDescription)\n")
            }
        } else {
            frpc.stop()
            serviceState = .stopped
        }
    }

    func toggleRunning() {
        setRunning(!isActive)
    }

    func stopService() {
        frpc.stop()
        serviceState = .stopped
    }

    func clearLog() {
        log = ""
    }

    private func appendLog(_ chunk: String) {
        log += chunk
        if log.count > maxLogLength {
            log = String(log.suffix(maxLogLength))
        }
        if serviceState == .starting, log.contains(successMarker) {
            serviceState = .running
        }
    }

    // MARK: - Login item

    private func applyLoginItem() {
        do {
            let status = SMAppService.mainApp.status
            if launchAtLogin {
                if status != .enabled {
                    try SMAppService.mainApp.register()
                }
            } else {
                if status == .enabled {
                    try SMAppService.mainApp.unregister()
                }
            }
        } catch {
            lastError = "Login item update failed: \(error.localizedDescription)"
        }
    }
}
