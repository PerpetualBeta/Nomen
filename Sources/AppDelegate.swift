import AppKit
import NomenCore
import SwiftUI
import Sparkle

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {

    /// How many recent renames the menu lists. The rest stay in the history for the
    /// record but would only make the menu long.
    static let recentInMenu = 5

    private var statusItem: NSStatusItem?
    let engine = NomenEngine()

    private let sparkleUserDriverDelegate = JorvikUserDriverDelegate()
    private lazy var sparkleUpdater = SPUStandardUpdaterController(
        startingUpdater: true,
        updaterDelegate: nil,
        userDriverDelegate: sparkleUserDriverDelegate
    )

    // MARK: - Lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        // There is no SwiftUI App to build a menu bar, so build one. It is never drawn, but
        // AppKit routes key equivalents through it: Command-Q and editing shortcuts.
        JorvikApplicationMenu.install()
        NSApp.setActivationPolicy(.accessory)

        createStatusItem()
        _ = sparkleUpdater  // starts Sparkle at launch

        NotificationCenter.default.addObserver(
            forName: JorvikStatusItemVisibility.didChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.applyStatusItemVisibility() }
        }
        // The pill is pre-rendered for the menu bar's thickness, which changes between a
        // notched display and an external one.
        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.updateIcon() }
        }

        engine.onHistoryChanged = { [weak self] in self?.updateIcon() }
        engine.start()
        updateIcon()
    }

    func applicationWillTerminate(_ notification: Notification) {
        engine.stop()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        JorvikStatusItemVisibility.handleReopen()
        return true
    }

    // MARK: - Status item

    private func createStatusItem() {
        guard JorvikStatusItemVisibility.isVisible else { return }
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem?.autosaveName = "NomenStatusItem"
        updateIcon()
        let menu = NSMenu()
        menu.delegate = self
        statusItem?.menu = menu
    }

    private func applyStatusItemVisibility() {
        if JorvikStatusItemVisibility.isVisible {
            if statusItem == nil { createStatusItem() }
        } else if let item = statusItem {
            NSStatusBar.system.removeStatusItem(item)
            statusItem = nil
        }
    }

    private func updateIcon() {
        statusItem?.button?.image = JorvikMenuBarPill.icon(
            symbolName: engine.isPaused ? "tag.slash" : "tag",
            accessibilityDescription: "Nomen"
        )
    }

    // MARK: - Menu (NSMenuDelegate)

    func menuNeedsUpdate(_ menu: NSMenu) {
        let recent = Array(engine.history.records.prefix(Self.recentInMenu))
        var actions: [JorvikMenuBuilder.ActionItem] = []

        let heading = recent.isEmpty
            ? L10n.string("menu.no_renames", defaultValue: "No screenshots renamed yet")
            : L10n.string("menu.recent", defaultValue: "Recently Renamed")
        actions.append(.init(title: heading, action: #selector(noop), target: self, isEnabled: false,
                             attributedTitle: secondary(heading)))
        for _ in recent {
            // Titles and submenus are filled in below: the builder has no submenu support.
            actions.append(.init(title: "", action: #selector(noop), target: self))
        }

        actions.append(.init(title: "-", action: #selector(noop), target: self))
        actions.append(.init(
            title: L10n.string("menu.pause", defaultValue: "Pause Naming"),
            action: #selector(togglePause), target: self, state: engine.isPaused ? .on : .off))
        actions.append(.init(
            title: L10n.string("menu.open_folder", defaultValue: "Open Screenshot Folder"),
            action: #selector(openFolder), target: self))
        actions.append(.init(title: "-", action: #selector(noop), target: self))
        actions.append(.init(
            title: L10n.string("menu.check_for_updates", defaultValue: "Check for Updates\u{2026}"),
            action: #selector(checkForUpdates(_:)), target: self))

        let built = JorvikMenuBuilder.buildMenu(
            appName: "Nomen",
            aboutAction: #selector(openAbout),
            settingsAction: #selector(openSettings),
            target: self,
            actions: actions
        )
        menu.removeAllItems()
        for item in built.items {
            built.removeItem(item)
            menu.addItem(item)
        }

        // Turn the placeholders that follow the heading into one item per rename.
        if let headingIndex = menu.items.firstIndex(where: { $0.title == heading }) {
            for (offset, record) in recent.enumerated() {
                let item = menu.items[headingIndex + 1 + offset]
                item.title = record.newName
                item.action = nil
                item.submenu = submenu(for: record)
                item.indentationLevel = 1
            }
        }
    }

    private func submenu(for record: RenameRecord) -> NSMenu {
        let sub = NSMenu()
        let show = NSMenuItem(title: L10n.string("menu.show_in_finder", defaultValue: "Show in Finder"),
                              action: #selector(showInFinder(_:)), keyEquivalent: "")
        show.target = self
        show.representedObject = record.id
        sub.addItem(show)

        let undo = NSMenuItem(
            title: L10n.format("menu.undo_format", defaultValue: "Undo: Back to \u{201C}%@\u{201D}", record.originalName),
            action: #selector(undoRename(_:)), keyEquivalent: "")
        undo.target = self
        undo.representedObject = record.id
        sub.addItem(undo)

        sub.addItem(.separator())
        let when = RelativeDateTimeFormatter().localizedString(for: record.date, relativeTo: Date())
        let info = NSMenuItem(title: "\(when) \u{00B7} \(record.method)", action: nil, keyEquivalent: "")
        info.isEnabled = false
        sub.addItem(info)
        return sub
    }

    private func secondary(_ s: String) -> NSAttributedString {
        NSAttributedString(string: s, attributes: [
            .font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize),
            .foregroundColor: NSColor.secondaryLabelColor,
        ])
    }

    // MARK: - Actions

    private func record(for sender: Any?) -> RenameRecord? {
        guard let id = (sender as? NSMenuItem)?.representedObject as? UUID else { return nil }
        return engine.history.records.first { $0.id == id }
    }

    @objc private func showInFinder(_ sender: Any?) {
        guard let record = record(for: sender) else { return }
        if FileManager.default.fileExists(atPath: record.newURL.path) {
            NSWorkspace.shared.activateFileViewerSelecting([record.newURL])
        } else {
            alert(L10n.format("alert.missing_format", defaultValue: "\u{201C}%@\u{201D} is no longer in the folder.", record.newName))
        }
    }

    @objc private func undoRename(_ sender: Any?) {
        guard let record = record(for: sender) else { return }
        switch engine.undo(record) {
        case .restored:
            break
        case .renamedFileMissing:
            alert(L10n.format("alert.missing_format", defaultValue: "\u{201C}%@\u{201D} is no longer in the folder.", record.newName))
        case .originalNameTaken:
            alert(L10n.format("alert.taken_format",
                              defaultValue: "Another file is already called \u{201C}%@\u{201D}, so the rename was not undone.",
                              record.originalName))
        case .failed(let reason):
            alert(reason)
        }
    }

    @objc private func togglePause() {
        engine.isPaused.toggle()
        updateIcon()
    }

    @objc private func openFolder() {
        NSWorkspace.shared.open(engine.folder)
    }

    @objc func checkForUpdates(_ sender: Any?) {
        NSRunningApplication.current.activate(options: [.activateAllWindows])
        sparkleUpdater.checkForUpdates(sender)
    }

    @objc private func noop() {}

    private func alert(_ text: String) {
        NSRunningApplication.current.activate(options: [.activateAllWindows])
        let a = NSAlert()
        a.messageText = text
        a.runModal()
    }

    // MARK: - About & Settings

    @objc private func openAbout() {
        JorvikAboutView.showWindow(appName: "Nomen", repoName: "Nomen", productPage: "utilities/nomen")
    }

    @objc private func openSettings() {
        let engine = self.engine
        JorvikSettingsView.showWindow(appName: "Nomen") {
            NomenSettingsContent(engine: engine)
        }
    }
}
