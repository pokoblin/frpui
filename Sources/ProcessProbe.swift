import Darwin

/// Detects whether a process with a given executable name is currently running,
/// across all users (so the GUI app can see the root-owned daemon's frpc).
enum ProcessProbe {
    static func isRunning(named target: String) -> Bool {
        let count = proc_listallpids(nil, 0)
        guard count > 0 else { return false }

        var pids = [pid_t](repeating: 0, count: Int(count))
        let written = proc_listallpids(&pids, Int32(Int(count) * MemoryLayout<pid_t>.stride))
        guard written > 0 else { return false }

        var nameBuffer = [CChar](repeating: 0, count: 1024)
        for pid in pids where pid > 0 {
            guard proc_name(pid, &nameBuffer, UInt32(nameBuffer.count)) > 0 else { continue }
            if String(cString: nameBuffer) == target { return true }
        }
        return false
    }
}
