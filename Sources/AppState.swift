import SwiftUI

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
        static let launchMode = "launchMode"
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

    @Published var launchMode: LaunchMode {
        didSet {
            UserDefaults.standard.set(launchMode.rawValue, forKey: Key.launchMode)
            if let message = LaunchManager.apply(launchMode, mirrorConfig: true) {
                lastError = message
            }
            reconcileMonitoring()
        }
    }

    @Published var serviceState: ServiceState = .stopped
    @Published var log: String = ""
    @Published var lastError: String?

    private let frpc = FRPCManager()
    private var daemonTimer: Timer?

    var isActive: Bool { serviceState != .stopped }

    private init() {
        let defaults = UserDefaults.standard
        defaults.register(defaults: [
            Key.appearance: AppAppearance.system.rawValue,
            Key.autoStartService: false,
            Key.launchMode: LaunchMode.off.rawValue,
        ])
        appearance = AppAppearance(rawValue: defaults.string(forKey: Key.appearance) ?? "") ?? .system
        autoStartService = defaults.bool(forKey: Key.autoStartService)
        launchMode = LaunchMode(rawValue: defaults.string(forKey: Key.launchMode) ?? "") ?? .off

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
        _ = LaunchManager.apply(launchMode, mirrorConfig: false)
        reconcileMonitoring()
        if autoStartService, launchMode != .systemDaemon {
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

    // MARK: - System daemon monitoring

    /// In system-daemon mode the daemon owns frpc, so we derive state by tailing its
    /// log file and probing for the frpc process instead of running a local one.
    private func reconcileMonitoring() {
        if launchMode == .systemDaemon {
            startDaemonMonitoring()
        } else {
            stopDaemonMonitoring()
        }
    }

    private func startDaemonMonitoring() {
        frpc.stop()
        log = ""
        serviceState = .stopped
        daemonTimer?.invalidate()
        pollDaemon()
        daemonTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            self?.pollDaemon()
        }
    }

    private func stopDaemonMonitoring() {
        guard daemonTimer != nil else { return }
        daemonTimer?.invalidate()
        daemonTimer = nil
        serviceState = .stopped
        log = ""
    }

    private func pollDaemon() {
        let tail = readDaemonLogTail(maxBytes: 64 * 1024)
        log = tail
        if !ProcessProbe.isRunning(named: "frpc") {
            serviceState = .stopped
        } else if tail.contains(successMarker) {
            serviceState = .running
        } else {
            serviceState = .starting
        }
    }

    private func readDaemonLogTail(maxBytes: Int) -> String {
        guard let handle = FileHandle(forReadingAtPath: LaunchManager.daemonLogPath) else { return "" }
        defer { try? handle.close() }
        let end = (try? handle.seekToEnd()) ?? 0
        let start = end > UInt64(maxBytes) ? end - UInt64(maxBytes) : 0
        try? handle.seek(toOffset: start)
        let data = (try? handle.readToEnd()) ?? Data()
        return String(decoding: data, as: UTF8.self)
    }

    // MARK: - System daemon config sync

    /// Mirror the saved config to the system location and restart the daemon.
    /// No-op unless the system-daemon mode is active.
    func syncSystemConfigIfNeeded() {
        guard launchMode == .systemDaemon else { return }
        if !LaunchManager.pushConfigAndReload() {
            lastError = "Failed to update the system service configuration."
        }
    }
}
