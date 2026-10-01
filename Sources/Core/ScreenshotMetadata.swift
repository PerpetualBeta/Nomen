import Foundation
import CoreGraphics

/// What macOS records on a screenshot file when it saves one.
///
/// screencaptureui writes these as extended attributes on the file itself
/// (`com.apple.metadata:kMDItemIsScreenCapture` and friends), so they can be read the moment
/// the file appears. Spotlight shows the same values through `mdls`, but only once it has
/// indexed the file, which can take seconds. Reading the attributes directly means Nomen
/// never waits on Spotlight, and it recognises a screenshot by what it is rather than by a
/// filename that changes with the user's language and settings.
public struct ScreenshotMetadata: Equatable {

    public enum CaptureType: String {
        case selection, window, display
        case other
    }

    public let type: CaptureType
    /// The captured area in global screen coordinates, top-left origin: the same space
    /// `CGWindowListCopyWindowInfo` reports window bounds in.
    public let rect: CGRect?

    public init(type: CaptureType, rect: CGRect?) {
        self.type = type
        self.rect = rect
    }

    static let flagKey = "com.apple.metadata:kMDItemIsScreenCapture"
    static let typeKey = "com.apple.metadata:kMDItemScreenCaptureType"
    static let rectKey = "com.apple.metadata:kMDItemScreenCaptureGlobalRect"

    /// The metadata, or nil when the file is not a macOS screenshot.
    public static func read(from url: URL) -> ScreenshotMetadata? {
        guard let flag = attribute(flagKey, of: url), isTrue(flag) else { return nil }
        let typeName = attribute(typeKey, of: url) as? String
        let rectValues = attribute(rectKey, of: url) as? [NSNumber]
        return make(typeName: typeName, rectValues: rectValues)
    }

    /// Builds the value from decoded attribute contents. Split out so it can be tested
    /// without a real screenshot.
    public static func make(typeName: String?, rectValues: [NSNumber]?) -> ScreenshotMetadata {
        let type = typeName.flatMap(CaptureType.init(rawValue:)) ?? .other
        var rect: CGRect?
        if let v = rectValues, v.count == 4 {
            let r = CGRect(x: v[0].doubleValue, y: v[1].doubleValue,
                           width: v[2].doubleValue, height: v[3].doubleValue)
            if r.width > 0, r.height > 0 { rect = r }
        }
        return ScreenshotMetadata(type: type, rect: rect)
    }

    private static func isTrue(_ value: Any) -> Bool {
        if let b = value as? Bool { return b }
        if let n = value as? NSNumber { return n.boolValue }
        return false
    }

    /// Reads one extended attribute and decodes it. These attributes hold binary plists.
    static func attribute(_ name: String, of url: URL) -> Any? {
        url.withUnsafeFileSystemRepresentation { path -> Any? in
            guard let path else { return nil }
            let size = getxattr(path, name, nil, 0, 0, 0)
            guard size > 0 else { return nil }
            var data = Data(count: size)
            let read = data.withUnsafeMutableBytes { getxattr(path, name, $0.baseAddress, size, 0, 0) }
            guard read == size else { return nil }
            return try? PropertyListSerialization.propertyList(from: data, format: nil)
        }
    }
}
