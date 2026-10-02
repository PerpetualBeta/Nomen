import Foundation

/// Removes a web browser's name from a screenshot's name.
///
/// A screenshot taken in a browser is of the page, never of the browser, so the browser's name
/// says nothing about it. The model still put it in: across four test runs on 2026-10-02 the
/// current prompts gave `jonathan-hollin-safari`, `safari-agreements-list` and
/// `safari-profile-menu-options`, three in sixty names. Telling the model not to fixed the leak
/// and cost detail elsewhere: "never name the browser" made it drop "apple-developer" from an
/// Apple agreements page in both runs. Nomen knows which app the screenshot came from, so it
/// removes the name itself, exactly, and the prompts stay as they were.
///
/// Only browsers. In Outlook or Teams the app is often part of what the screenshot is about
/// (`outlook-error-dates`), so other apps' names stay.
public enum BrowserName {

    /// Browsers by the name macOS reports as the window's owner, each with the slug words
    /// that name becomes. "Google Chrome" is matched as "google-chrome" and as "chrome".
    static let browsers: [String: [[String]]] = [
        "Safari":                [["safari"]],
        "Safari Technology Preview": [["safari", "technology", "preview"], ["safari"]],
        "Google Chrome":         [["google", "chrome"], ["chrome"]],
        "Google Chrome Canary":  [["google", "chrome", "canary"], ["chrome", "canary"], ["chrome"]],
        "Chromium":              [["chromium"]],
        "Firefox":               [["firefox"]],
        "Firefox Developer Edition": [["firefox", "developer", "edition"], ["firefox"]],
        "Microsoft Edge":        [["microsoft", "edge"], ["edge"]],
        "Arc":                   [["arc"]],
        "Brave Browser":         [["brave", "browser"], ["brave"]],
        "Opera":                 [["opera"]],
        "Vivaldi":               [["vivaldi"]],
        "Orion":                 [["orion"]],
        "DuckDuckGo":            [["duckduckgo"]],
        "Zen":                   [["zen"]],
    ]

    /// The fewest words a name may keep. If removing the browser would leave less, the name is
    /// returned as it was: a one-word name says less than one that mentions the browser.
    public static let minimumWords = 2

    /// `stem` without the words naming `appName`, when `appName` is a web browser.
    public static func strip(_ stem: String, appName: String?) -> String {
        guard let appName, let patterns = browsers[appName] else { return stem }
        var words = stem.split(separator: "-").map(String.init)
        // Longest pattern first, so "google-chrome" goes as a pair before "chrome" alone.
        for pattern in patterns.sorted(by: { $0.count > $1.count }) {
            var i = 0
            while i + pattern.count <= words.count {
                if Array(words[i..<(i + pattern.count)]) == pattern {
                    words.removeSubrange(i..<(i + pattern.count))
                } else {
                    i += 1
                }
            }
        }
        guard words.count >= minimumWords else { return stem }
        return words.joined(separator: "-")
    }
}
