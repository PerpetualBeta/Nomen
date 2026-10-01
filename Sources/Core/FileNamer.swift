import Foundation

/// Builds the final filename from a stem and picks one that is free in the folder.
public enum FileNamer {

    /// The name to rename to, given a cleaned stem. `captureDate` is appended only when the
    /// user asked to keep dates, in the same "at HH.MM.SS" shape macOS uses, so a renamed
    /// screenshot still sorts and searches the way the original did.
    public static func filename(stem: String, ext: String, captureDate: Date?, keepDate: Bool) -> String {
        var base = stem
        if keepDate, let captureDate {
            base += " " + dateFormatter.string(from: captureDate)
        }
        return ext.isEmpty ? base : base + "." + ext
    }

    /// `filename`, or the first `stem-2`, `stem-3`… that `isTaken` says is free.
    ///
    /// Two screenshots of the same thing get the same name. Overwriting would delete one,
    /// and failing would leave the second with its original name for no visible reason,
    /// so the second gets a number, as Finder does for duplicates.
    public static func available(_ filename: String, isTaken: (String) -> Bool) -> String? {
        guard isTaken(filename) else { return filename }
        let url = URL(fileURLWithPath: filename)
        let ext = url.pathExtension
        let stem = url.deletingPathExtension().lastPathComponent
        for n in 2...999 {
            let candidate = ext.isEmpty ? "\(stem)-\(n)" : "\(stem)-\(n).\(ext)"
            if !isTaken(candidate) { return candidate }
        }
        return nil
    }

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
        return f
    }()
}
