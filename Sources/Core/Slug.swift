import Foundation

/// Turns whatever the namer produced into a safe, tidy filename stem.
///
/// The on-device model is asked for a hyphenated slug, but a small model does not always
/// do as it is asked: it adds quotes, an extension, a full stop, a second line of
/// explanation, or capitals. Everything it returns goes through here, so a bad reply can
/// cost a good name but can never produce a bad file.
public enum Slug {

    /// Most words a name may keep. Past this a name stops being a label and becomes a
    /// sentence, and Finder truncates it in the middle anyway.
    public static let maxWords = 8

    /// Longest stem, in characters. APFS allows 255 bytes; this leaves room for the
    /// extension, a collision suffix and an optional date.
    public static let maxLength = 80

    /// Cleans `raw` into a lowercase, hyphen-separated stem. Returns nil when nothing
    /// usable is left, so the caller falls back rather than renaming to an empty name.
    public static func make(from raw: String) -> String? {
        // Only the first line: a model that explains itself does so on the next line.
        let firstLine = raw.split(whereSeparator: \.isNewline).first.map(String.init) ?? raw
        // Quotes and a closing full stop around the reply come off first, or they hide an
        // extension from the check below: `"name.png".` does not end in ".png".
        let wrappers = CharacterSet(charactersIn: "\"'`\u{201C}\u{201D}\u{2018}\u{2019}.,;:!?()[]{}<>*")
        var text = firstLine.trimmingCharacters(in: wrappers.union(.whitespacesAndNewlines))

        // A model that adds an extension usually adds the right one, but Nomen keeps the
        // file's real extension itself, so strip any it was handed.
        for ext in [".png", ".jpg", ".jpeg", ".heic", ".tiff", ".pdf"] where text.lowercased().hasSuffix(ext) {
            text = String(text.dropLast(ext.count))
        }

        // Letters and digits from any script survive; everything else becomes a separator.
        // Folding diacritics keeps names typeable without losing what they say.
        let folded = text.folding(options: [.diacriticInsensitive, .widthInsensitive], locale: nil).lowercased()
        let words = folded
            .split(whereSeparator: { !($0.isLetter || $0.isNumber) })
            .map(String.init)
            .filter { !$0.isEmpty }
        guard !words.isEmpty else { return nil }

        // Repeated words go: the model echoes its description, and "a man in a white lab
        // coat in a lab" became man-lab-coat-white-lab-coat-lab. The first use is kept, so
        // the order still reads as a phrase.
        var unique: [String] = []
        var seen = Set<String>()
        for word in words where seen.insert(word).inserted { unique.append(word) }

        var kept: [String] = []
        var length = 0
        for word in unique.prefix(maxWords) {
            let added = (kept.isEmpty ? 0 : 1) + word.count
            if length + added > maxLength { break }
            kept.append(word)
            length += added
        }
        // A single word longer than the limit: keep its start rather than nothing.
        if kept.isEmpty, let first = words.first { kept = [String(first.prefix(maxLength))] }
        return kept.joined(separator: "-")
    }
}
