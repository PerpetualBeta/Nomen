import Cocoa

/// The entry point. Deliberately not a SwiftUI `App`.
///
/// `App` must vend at least one scene, and a menu-bar app's only candidate is a
/// `Settings { EmptyView() }` placeholder. On macOS 26 and later that placeholder opens as
/// a blank window at launch. The settings window comes from the status-item menu instead,
/// via `JorvikSettingsView.showWindow`.
///
/// `@main` on a type rather than top-level code in a `main.swift`, because `AppDelegate` is
/// `@MainActor` and top-level code is not isolated to it.
@main
enum NomenMain {

    @MainActor
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.run()
    }
}
