import Foundation

enum FRPCError: LocalizedError {
    case binaryMissing

    var errorDescription: String? {
        switch self {
        case .binaryMissing:
            return "The bundled frpc binary was not found in the app."
        }
    }
}

/// Manages the frpc child process. All mutating calls are expected on the main thread;
/// the output and termination callbacks are hopped back to the main thread.
final class FRPCManager {
    private var process: Process?
    private var outputPipe: Pipe?

    /// Streamed stdout/stderr chunks from frpc.
    var onOutput: ((String) -> Void)?

    /// Called when the process exits on its own (crash, bad config, manual kill).
    var onTerminate: (() -> Void)?

    var isRunning: Bool { process?.isRunning ?? false }

    func start() throws {
        guard process == nil else { return }

        guard let exe = Bundle.main.url(forResource: "frpc", withExtension: nil) else {
            throw FRPCError.binaryMissing
        }
        try? FileManager.default.setAttributes(
            [.posixPermissions: 0o755], ofItemAtPath: exe.path)

        ConfigStore.ensureSeeded()
        let configURL = ConfigStore.configURL

        let p = Process()
        p.executableURL = exe
        p.arguments = ["-c", configURL.path]
        p.currentDirectoryURL = configURL.deletingLastPathComponent()

        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = pipe
        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
            DispatchQueue.main.async { self?.onOutput?(text) }
        }
        outputPipe = pipe

        p.terminationHandler = { [weak self] _ in
            DispatchQueue.main.async {
                guard let self else { return }
                self.cleanupPipe()
                self.process = nil
                self.onTerminate?()
            }
        }

        try p.run()
        process = p
    }

    func stop() {
        guard let p = process else { return }
        process = nil
        p.terminationHandler = nil
        cleanupPipe()
        if p.isRunning {
            p.terminate()
        }
    }

    private func cleanupPipe() {
        outputPipe?.fileHandleForReading.readabilityHandler = nil
        outputPipe = nil
    }
}
