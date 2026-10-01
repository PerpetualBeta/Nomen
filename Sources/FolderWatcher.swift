import Foundation

/// Calls back when the contents of one folder change.
///
/// A vnode source on the folder's descriptor fires on every entry added, removed or renamed
/// in it, which is all Nomen needs: it then lists the folder itself and decides what is new.
/// FSEvents would add history and recursion that a single screenshot folder does not use.
/// Events arrive in bursts (screencaptureui writes, renames and sets attributes in quick
/// succession), so they are coalesced into one callback after a short quiet period.
final class FolderWatcher {

    /// Quiet time after the last event before the folder is looked at. Long enough to fold
    /// one save's burst of events into one look, short enough to feel immediate.
    static let coalesceDelay: TimeInterval = 0.4

    let folder: URL
    private let onChange: () -> Void
    private var source: DispatchSourceFileSystemObject?
    private var pending: DispatchWorkItem?

    init?(folder: URL, onChange: @escaping () -> Void) {
        self.folder = folder
        self.onChange = onChange
        let fd = open(folder.path, O_EVTONLY)
        guard fd >= 0 else {
            nmLog("watcher: cannot open \(folder.path) (errno \(errno))")
            return nil
        }
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd, eventMask: [.write, .rename, .delete], queue: .main)
        source.setEventHandler { [weak self] in self?.schedule() }
        source.setCancelHandler { close(fd) }
        self.source = source
        source.resume()
        nmLog("watcher: watching \(folder.path)")
    }

    deinit { source?.cancel() }

    func stop() {
        pending?.cancel()
        source?.cancel()
        source = nil
    }

    private func schedule() {
        pending?.cancel()
        let item = DispatchWorkItem { [weak self] in self?.onChange() }
        pending = item
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.coalesceDelay, execute: item)
    }
}
