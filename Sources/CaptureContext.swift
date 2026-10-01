import AppKit
import NomenCore

/// Which app a screenshot came from.
///
/// Uses the captured rectangle macOS records on the file, matched against the windows on
/// screen now. App names come from `kCGWindowOwnerName`, which needs no permission. Window
/// titles would need Screen Recording, and Nomen does not ask for it, so titles are only
/// used if the user has granted that for some other reason.
enum CaptureContext {

    struct Context {
        let appName: String?
        let windowTitle: String?
    }

    static func find(for metadata: ScreenshotMetadata) -> Context {
        switch metadata.type {
        case .display:
            // A whole-display capture is of everything; the app in front is the best guess.
            return Context(appName: frontmostAppName(), windowTitle: nil)
        default:
            guard let rect = metadata.rect else {
                return Context(appName: frontmostAppName(), windowTitle: nil)
            }
            if let w = WindowPicker.pick(for: rect, among: onScreenWindows()) {
                let title = (w.title?.isEmpty ?? true) ? nil : w.title
                return Context(appName: w.ownerName, windowTitle: title)
            }
            return Context(appName: nil, windowTitle: nil)
        }
    }

    private static func frontmostAppName() -> String? {
        let app = NSWorkspace.shared.frontmostApplication
        return app?.bundleIdentifier == Bundle.main.bundleIdentifier ? nil : app?.localizedName
    }

    /// On-screen windows, front to back, as `WindowPicker` expects.
    static func onScreenWindows() -> [WindowInfo] {
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements],
                                                    kCGNullWindowID) as? [[String: Any]] else { return [] }
        return list.compactMap { d in
            guard let owner = d[kCGWindowOwnerName as String] as? String,
                  let pid = d[kCGWindowOwnerPID as String] as? Int32,
                  let layer = d[kCGWindowLayer as String] as? Int,
                  let bd = d[kCGWindowBounds as String] as? [String: Any],
                  let bounds = CGRect(dictionaryRepresentation: bd as CFDictionary) else { return nil }
            return WindowInfo(ownerName: owner, ownerPID: pid,
                              title: d[kCGWindowName as String] as? String,
                              bounds: bounds, layer: layer)
        }
    }
}
