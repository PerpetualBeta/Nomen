import Foundation

/// The fallback when the on-device model is unavailable: Apple Intelligence off, an Intel
/// Mac, macOS before 26, or the model failing on this one image.
///
/// It cannot understand a screenshot, so it does not pretend to. It names the app the
/// capture came from, then adds the first few substantial words of the recognised text,
/// which is usually the title or heading. That is less elegant than the model's name, but
/// every word in it is really there.
public enum RuleNamer {

    /// Words too common to say anything about a screenshot.
    static let stopWords: Set<String> = [
        "the", "a", "an", "and", "or", "of", "to", "in", "on", "for", "with", "is", "it",
        "this", "that", "be", "are", "was", "at", "by", "from", "as", "you", "your", "i",
    ]

    public static func name(appName: String?, recognisedText: String, wordLimit: Int = 4) -> String? {
        var words: [String] = []
        if let appName, let appSlug = Slug.make(from: appName) { words.append(appSlug) }
        let textWords = recognisedText
            .split(whereSeparator: { !($0.isLetter || $0.isNumber) })
            .map { $0.lowercased() }
            .filter { $0.count >= 3 && !stopWords.contains($0) && !$0.allSatisfy(\.isNumber) }
        var seen = Set(words)
        for w in textWords where !seen.contains(w) {
            words.append(w)
            seen.insert(w)
            if words.count >= wordLimit + (appName == nil ? 0 : 1) { break }
        }
        return Slug.make(from: words.joined(separator: " "))
    }
}
