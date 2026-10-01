import Foundation

// Diagnostic logging — off by default, enabled per-machine via:
//   defaults write cc.jorviksoftware.Nomen debugLogging -bool YES
//   defaults delete cc.jorviksoftware.Nomen debugLogging   # turn off
// When on, timestamped lines are appended to
//   ~/Library/Logs/Nomen/nomen.log
//
// Never write to Console/stderr or /tmp. This mirrors the Jorvik logging convention: a
// symlink-safe append to a 0700 directory, gated behind a UserDefaults flag read on every
// call. Names and recognised text are screenshot contents, so the log stays on this Mac
// and is never written unless the user turns it on.
private let nmLogPath: String = {
    let logs = FileManager.default
        .urls(for: .libraryDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("Logs", isDirectory: true)
        .appendingPathComponent("Nomen", isDirectory: true)
    try? FileManager.default.createDirectory(at: logs, withIntermediateDirectories: true,
                                             attributes: [.posixPermissions: 0o700])
    return logs.appendingPathComponent("nomen.log").path
}()
private let nmLogQueue = DispatchQueue(label: "cc.jorviksoftware.Nomen.log")
private let nmLogFmt: DateFormatter = {
    let f = DateFormatter()
    f.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
    return f
}()

func nmLog(_ msg: String) {
    guard UserDefaults.standard.bool(forKey: "debugLogging") else { return }
    let line = "\(nmLogFmt.string(from: Date()))  \(msg)\n"
    nmLogQueue.async {
        guard let data = line.data(using: .utf8) else { return }
        // O_NOFOLLOW + 0700 parent dir closes the symlink-attack vector.
        let fd = open(nmLogPath, O_WRONLY | O_APPEND | O_CREAT | O_NOFOLLOW, 0o600)
        guard fd >= 0 else { return }
        defer { close(fd) }
        data.withUnsafeBytes { _ = write(fd, $0.baseAddress, $0.count) }
    }
}
