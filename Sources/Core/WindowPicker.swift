import Foundation
import CoreGraphics

/// One on-screen window, as far as Nomen cares.
public struct WindowInfo: Equatable {
    public let ownerName: String
    public let ownerPID: Int32
    public let title: String?
    public let bounds: CGRect
    public let layer: Int

    public init(ownerName: String, ownerPID: Int32, title: String?, bounds: CGRect, layer: Int) {
        self.ownerName = ownerName
        self.ownerPID = ownerPID
        self.title = title
        self.bounds = bounds
        self.layer = layer
    }
}

/// Decides which window a screenshot was taken of.
///
/// The file reaches the folder about five seconds after the capture, once the floating
/// thumbnail has gone, so asking "what is frontmost now" can answer with whatever the user
/// clicked next. The captured rectangle is recorded on the file, though, and windows rarely
/// move in those five seconds, so the window under that rectangle is the better witness.
public enum WindowPicker {

    /// Owners that are never what a screenshot is "of": the capture UI itself, and system
    /// surfaces that sit over everything. On macOS 27 the Dock owns an invisible window
    /// covering the whole screen, so without this every hit test would find the Dock.
    public static let ignoredOwners: Set<String> = [
        "Dock", "Window Server", "WindowManager", "screencaptureui", "Screenshot",
        "Control Centre", "Control Center", "Notification Centre", "Notification Center",
        "SystemUIServer", "Nomen",
    ]

    /// How much of the captured area a window must cover to count. Below this the capture
    /// was mostly of something else, and naming it after this window would mislead.
    public static let minimumCoverage = 0.5

    /// The best window for `rect`, or nil. `windows` must be front to back, which is the
    /// order `CGWindowListCopyWindowInfo` returns.
    public static func pick(for rect: CGRect, among windows: [WindowInfo]) -> WindowInfo? {
        let area = rect.width * rect.height
        guard area > 0 else { return nil }
        for w in windows where w.layer == 0 && !ignoredOwners.contains(w.ownerName) {
            let overlap = w.bounds.intersection(rect)
            guard !overlap.isNull else { continue }
            if Double(overlap.width * overlap.height / area) >= minimumCoverage { return w }
        }
        return nil
    }
}
