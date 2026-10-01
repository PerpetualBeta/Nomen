import AppKit
import NomenCore

/// Watches the screenshot folder and renames each new screenshot once.
///
/// Only screenshots that arrive while Nomen runs are touched. Renaming a folder of old
/// screenshots on first launch would be a surprise nobody asked for, and is the one thing
/// here that could not be undone in bulk.
@MainActor
final class NomenEngine: ObservableObject {

    /// The extended attribute Nomen puts on a file it has renamed. A screenshot restored by
    /// undo keeps it, so Nomen never renames the same screenshot twice.
    static let markerAttribute = "cc.jorviksoftware.Nomen.renamed"

    /// How long a file's size must hold still before it is read. screencaptureui writes the
    /// file in one go, but a slow disk or a large Retina capture can still be caught mid-write.
    static let stabilityInterval: TimeInterval = 0.5

    /// How often the screenshot location is re-read, in case the user changed it in the
    /// Screenshot app while Nomen runs. No notification is posted for that change.
    static let folderRecheckInterval: TimeInterval = 30

    @Published private(set) var history: RenameHistory
    @Published private(set) var folder: URL
    @Published private(set) var isWorking = false

    @Published var isPaused: Bool = UserDefaults.standard.bool(forKey: "paused") {
        didSet { UserDefaults.standard.set(isPaused, forKey: "paused") }
    }
    @Published var keepDate: Bool = UserDefaults.standard.bool(forKey: "keepDate") {
        didSet { UserDefaults.standard.set(keepDate, forKey: "keepDate") }
    }

    var onHistoryChanged: (() -> Void)?

    private var watcher: FolderWatcher?
    private var recheckTimer: Timer?
    private var startDate = Date()
    /// Files already looked at, by inode rather than path. A rename keeps the inode, so a
    /// screenshot the user renames before Nomen reaches it, or one Nomen has just renamed,
    /// is not mistaken for a new file under its new name.
    private var seen = Set<UInt64>()
    private var queue: [URL] = []

    init() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Nomen", isDirectory: true)
        history = RenameHistory(fileURL: support.appendingPathComponent("history.json"))
        folder = ScreenshotFolder.current()
    }

    func start() {
        startDate = Date()
        Namer.warmUp()
        nmLog("engine: started; model state \(Namer.modelState)")
        watch(ScreenshotFolder.current())
        recheckTimer = Timer.scheduledTimer(withTimeInterval: Self.folderRecheckInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.recheckFolder() }
        }
    }

    func stop() {
        watcher?.stop()
        recheckTimer?.invalidate()
    }

    private func watch(_ url: URL) {
        watcher?.stop()
        folder = url
        watcher = FolderWatcher(folder: url) { [weak self] in
            Task { @MainActor in self?.scan() }
        }
    }

    private func recheckFolder() {
        let current = ScreenshotFolder.current()
        guard current.standardizedFileURL != folder.standardizedFileURL else { return }
        nmLog("engine: screenshot folder changed to \(current.path)")
        watch(current)
    }

    // MARK: - Finding new screenshots

    private func scan() {
        guard !isPaused else { return }
        let keys: [URLResourceKey] = [.creationDateKey, .isRegularFileKey]
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: folder, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles]) else { return }
        for url in entries {
            guard let inode = inode(of: url), !seen.contains(inode) else { continue }
            let values = try? url.resourceValues(forKeys: Set(keys))
            guard values?.isRegularFile == true,
                  let created = values?.creationDate, created >= startDate else { continue }
            guard !hasMarker(url), ScreenshotMetadata.read(from: url) != nil else { continue }
            seen.insert(inode)
            queue.append(url)
            nmLog("engine: new screenshot \(url.lastPathComponent)")
        }
        processNext()
    }

    private func processNext() {
        guard !isWorking, !queue.isEmpty else { return }
        let url = queue.removeFirst()
        isWorking = true
        Task {
            await process(url)
            isWorking = false
            processNext()
        }
    }

    // MARK: - Renaming one screenshot

    private func process(_ url: URL) async {
        guard let metadata = ScreenshotMetadata.read(from: url) else { return }
        // Context first, before anything slow: the windows on screen are the witness, and
        // the longer Nomen waits the more likely the user has moved on.
        let context = CaptureContext.find(for: metadata)
        nmLog("engine: \(url.lastPathComponent) is a \(metadata.type.rawValue) capture of \(context.appName ?? "unknown app")")

        guard await waitUntilStable(url) else {
            nmLog("engine: \(url.lastPathComponent) never settled; left alone")
            return
        }
        guard let result = await Namer.name(imageAt: url, context: context) else {
            nmLog("engine: no name for \(url.lastPathComponent); left alone")
            return
        }
        rename(url, to: result.stem, method: result.method)
    }

    private func waitUntilStable(_ url: URL) async -> Bool {
        var last = fileSize(url)
        for _ in 0..<20 {
            try? await Task.sleep(nanoseconds: UInt64(Self.stabilityInterval * 1_000_000_000))
            let now = fileSize(url)
            if let now, now > 0, now == last { return true }
            last = now
        }
        return false
    }

    private func inode(of url: URL) -> UInt64? {
        (try? FileManager.default.attributesOfItem(atPath: url.path)[.systemFileNumber] as? NSNumber)?.uint64Value
    }

    private func fileSize(_ url: URL) -> Int? {
        (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.intValue
    }

    private func rename(_ url: URL, to stem: String, method: String) {
        let fm = FileManager.default
        guard fm.fileExists(atPath: url.path) else {
            nmLog("engine: \(url.lastPathComponent) has gone; nothing to rename")
            return
        }
        let dir = url.deletingLastPathComponent()
        let wanted = FileNamer.filename(stem: stem, ext: url.pathExtension.lowercased(),
                                        captureDate: captureDate(of: url), keepDate: keepDate)
        guard let target = FileNamer.available(wanted, isTaken: {
            fm.fileExists(atPath: dir.appendingPathComponent($0).path)
        }) else { return }
        let newURL = dir.appendingPathComponent(target)
        do {
            try fm.moveItem(at: url, to: newURL)
        } catch {
            nmLog("engine: rename of \(url.lastPathComponent) failed: \(error.localizedDescription)")
            return
        }
        setMarker(newURL)
        history.add(RenameRecord(folder: dir.path, originalName: url.lastPathComponent,
                                 newName: target, date: Date(), method: method))
        nmLog("engine: renamed \(url.lastPathComponent) -> \(target) [\(method)]")
        onHistoryChanged?()
    }

    /// The capture time in the original name ("… 2026-10-01 at 14.04.21"), which is when
    /// the screenshot was taken. The file's creation date is about five seconds later,
    /// when the floating thumbnail went away, so it is only the fallback.
    private func captureDate(of url: URL) -> Date? {
        let name = url.deletingPathExtension().lastPathComponent
        if let match = name.range(of: #"\d{4}-\d{2}-\d{2} at \d{1,2}\.\d{2}\.\d{2}"#, options: .regularExpression) {
            let f = DateFormatter()
            f.locale = Locale(identifier: "en_US_POSIX")
            f.dateFormat = "yyyy-MM-dd 'at' H.mm.ss"
            if let d = f.date(from: String(name[match])) { return d }
        }
        return (try? url.resourceValues(forKeys: [.creationDateKey]))?.creationDate
    }

    // MARK: - Undo

    enum UndoOutcome { case restored, renamedFileMissing, originalNameTaken, failed(String) }

    func undo(_ record: RenameRecord) -> UndoOutcome {
        let fm = FileManager.default
        guard fm.fileExists(atPath: record.newURL.path) else { return .renamedFileMissing }
        guard !fm.fileExists(atPath: record.originalURL.path) else { return .originalNameTaken }
        do {
            try fm.moveItem(at: record.newURL, to: record.originalURL)
        } catch {
            return .failed(error.localizedDescription)
        }
        history.remove(id: record.id)
        nmLog("engine: undid \(record.newName) -> \(record.originalName)")
        onHistoryChanged?()
        return .restored
    }

    // MARK: - Marker attribute

    private func hasMarker(_ url: URL) -> Bool {
        url.withUnsafeFileSystemRepresentation { path in
            guard let path else { return false }
            return getxattr(path, Self.markerAttribute, nil, 0, 0, 0) >= 0
        }
    }

    private func setMarker(_ url: URL) {
        url.withUnsafeFileSystemRepresentation { path in
            guard let path else { return }
            var one: UInt8 = 1
            _ = setxattr(path, Self.markerAttribute, &one, 1, 0, 0)
        }
    }
}
