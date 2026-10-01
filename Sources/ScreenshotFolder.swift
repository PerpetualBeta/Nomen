import Foundation

/// Where macOS saves screenshots.
///
/// The Screenshot app (shift-command-5 > Options > Save to) writes the choice to
/// `com.apple.screencapture`'s `location`. When it has never been set, macOS saves to the
/// Desktop. The value is another app's preference, and a running process caches other
/// domains, so it is synchronised before every read: otherwise a change the user makes
/// while Nomen runs would never be seen.
enum ScreenshotFolder {

    static let domain = "com.apple.screencapture" as CFString

    static func current() -> URL {
        CFPreferencesAppSynchronize(domain)
        if let raw = CFPreferencesCopyAppValue("location" as CFString, domain) as? String,
           !raw.trimmingCharacters(in: .whitespaces).isEmpty {
            let path = (raw as NSString).expandingTildeInPath
            var isDir: ObjCBool = false
            if FileManager.default.fileExists(atPath: path, isDirectory: &isDir), isDir.boolValue {
                return URL(fileURLWithPath: path, isDirectory: true)
            }
            nmLog("screenshot location \(raw) is not a folder; using the Desktop")
        }
        return FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask)[0]
    }
}
