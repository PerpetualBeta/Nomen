import Foundation

/// One rename Nomen made, kept so it can be undone.
public struct RenameRecord: Codable, Equatable, Identifiable {
    public let id: UUID
    public let folder: String
    public let originalName: String
    public let newName: String
    public let date: Date
    /// How the name was made: "model", "model (text)" or "rules". Shown in the log, and
    /// kept so a run of bad names can be traced to the path that produced them.
    public let method: String

    public init(folder: String, originalName: String, newName: String, date: Date, method: String) {
        self.id = UUID()
        self.folder = folder
        self.originalName = originalName
        self.newName = newName
        self.date = date
        self.method = method
    }

    public var newURL: URL { URL(fileURLWithPath: folder).appendingPathComponent(newName) }
    public var originalURL: URL { URL(fileURLWithPath: folder).appendingPathComponent(originalName) }
}

/// The last few renames, newest first, persisted as JSON.
///
/// A small model sometimes names a screenshot badly. Undo is what makes that harmless, so
/// the history survives a relaunch: a bad name noticed tomorrow can still be put back.
public struct RenameHistory {

    public static let capacity = 20

    public private(set) var records: [RenameRecord]
    private let fileURL: URL?

    public init(fileURL: URL?) {
        self.fileURL = fileURL
        if let fileURL, let data = try? Data(contentsOf: fileURL),
           let decoded = try? Self.decoder.decode([RenameRecord].self, from: data) {
            records = decoded
        } else {
            records = []
        }
    }

    public mutating func add(_ record: RenameRecord) {
        records.insert(record, at: 0)
        if records.count > Self.capacity { records.removeLast(records.count - Self.capacity) }
        save()
    }

    public mutating func remove(id: UUID) {
        records.removeAll { $0.id == id }
        save()
    }

    private func save() {
        guard let fileURL else { return }
        try? FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(),
                                                 withIntermediateDirectories: true)
        if let data = try? Self.encoder.encode(records) {
            try? data.write(to: fileURL, options: .atomic)
        }
    }

    private static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return e
    }()
    private static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()
}
