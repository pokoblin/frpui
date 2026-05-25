import Foundation

enum ConfigStore {
    static let fileName = "frpc.toml"

    static var supportDirectory: URL {
        let base = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first!
        return base.appendingPathComponent("frpui", isDirectory: true)
    }

    static var configURL: URL {
        supportDirectory.appendingPathComponent(fileName)
    }

    /// Create the support directory and seed frpc.toml from the bundle on first run.
    static func ensureSeeded() {
        let fm = FileManager.default
        try? fm.createDirectory(at: supportDirectory, withIntermediateDirectories: true)
        guard !fm.fileExists(atPath: configURL.path) else { return }
        if let seed = Bundle.main.url(forResource: "frpc", withExtension: "toml") {
            try? fm.copyItem(at: seed, to: configURL)
        } else {
            fm.createFile(atPath: configURL.path, contents: Data())
        }
    }

    static func read() -> String {
        ensureSeeded()
        return (try? String(contentsOf: configURL, encoding: .utf8)) ?? ""
    }

    static func write(_ text: String) throws {
        ensureSeeded()
        try text.write(to: configURL, atomically: true, encoding: .utf8)
    }
}
