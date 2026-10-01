import Foundation

// Diagnostic logging — off by default, enabled per-machine via:
//   defaults write cc.jorviksoftware.Nomen debugLogging -bool YES
//   defaults delete cc.jorviksoftware.Nomen debugLogging   # turn off
// When on, timestamped lines are appended to
//   ~/Library/Logs/Nomen/nomen.log
// and the run before the last rotation is kept in nomen.log.1.
//
// Never write to Console/stderr or /tmp. This mirrors the Jorvik logging convention: a
// symlink-safe append to a 0700 directory, gated behind a UserDefaults flag read on every
// call. Names, descriptions and recognised text are screenshot contents, so the log stays
// on this Mac, is private to this user, and is never written unless the user turns it on.
private let nmLogDirectory: URL = FileManager.default
    .urls(for: .libraryDirectory, in: .userDomainMask)[0]
    .appendingPathComponent("Logs", isDirectory: true)
    .appendingPathComponent("Nomen", isDirectory: true)
private let nmLogPath = nmLogDirectory.appendingPathComponent("nomen.log").path
private let nmPreviousLogPath = nmLogDirectory.appendingPathComponent("nomen.log.1").path

private let nmLogQueue = DispatchQueue(label: "cc.jorviksoftware.Nomen.log")
private let nmLogFmt: DateFormatter = {
    let f = DateFormatter()
    f.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
    return f
}()

/// Rotate once the live log passes this many bytes, keeping one previous generation, so
/// the logs can never occupy more than twice this figure.
///
/// 4 MB by default, as in MenuTidy, which added rotation on 2026-09-20. Each screenshot
/// writes about five lines, under 1 KB with its description, so 4 MB holds thousands of
/// screenshots. A knob, because a long tuning session may want more:
///
///     defaults write cc.jorviksoftware.Nomen debugLogMaxBytes -int 20971520
private var nmLogMaxBytes: Int {
    let stored = UserDefaults.standard.integer(forKey: "debugLogMaxBytes")
    return stored > 0 ? stored : 4 * 1024 * 1024
}

/// Takes its message as an autoclosure, so a disabled call builds no string.
func nmLog(_ msg: @autoclosure () -> String) {
    guard UserDefaults.standard.bool(forKey: "debugLogging") else { return }
    let line = "\(nmLogFmt.string(from: Date()))  \(msg())\n"
    let limit = nmLogMaxBytes
    nmLogQueue.async {
        nmAppend(line)
        // One process and one serial queue write this file, so the size read here is
        // the file just written to, and nothing can rotate it in between. MenuTidy also
        // follows the inode, because two of its processes share one log; Nomen has no
        // second writer to follow.
        var info = stat()
        guard stat(nmLogPath, &info) == 0, info.st_size >= limit else { return }
        unlink(nmPreviousLogPath)
        guard rename(nmLogPath, nmPreviousLogPath) == 0 else { return }
        nmAppend("\(nmLogFmt.string(from: Date()))  log rotated at \(info.st_size) bytes; the run before this is in nomen.log.1\n")
    }
}

/// Appends one line. Runs on `nmLogQueue` only.
private func nmAppend(_ line: String) {
    guard let data = line.data(using: .utf8) else { return }
    try? FileManager.default.createDirectory(at: nmLogDirectory, withIntermediateDirectories: true,
                                             attributes: [.posixPermissions: 0o700])
    // O_NOFOLLOW + 0700 parent dir closes the symlink-attack vector.
    let fd = open(nmLogPath, O_WRONLY | O_APPEND | O_CREAT | O_NOFOLLOW, 0o600)
    guard fd >= 0 else { return }
    defer { close(fd) }
    data.withUnsafeBytes { _ = write(fd, $0.baseAddress, $0.count) }
}
