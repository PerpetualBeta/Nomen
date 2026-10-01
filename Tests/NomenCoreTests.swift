import XCTest
import CoreGraphics
@testable import NomenCore

final class SlugTests: XCTestCase {

    func testPlainSlugPassesThrough() {
        XCTAssertEqual(Slug.make(from: "rmw-pr-48-space-capture"), "rmw-pr-48-space-capture")
    }

    func testModelNoiseIsStripped() {
        // Quotes, capitals, an extension, a full stop and an explanation on the next line.
        XCTAssertEqual(Slug.make(from: "\"Stripe Dashboard Revenue.png\".\nThis shows revenue."),
                       "stripe-dashboard-revenue")
    }

    func testRepeatedWordsAreDropped() {
        // A real reply from the on-device model, 2026-10-01.
        XCTAssertEqual(Slug.make(from: "man-lab-coat-white-lab-coat-lab"), "man-lab-coat-white")
    }

    func testDiacriticsAreFolded() {
        XCTAssertEqual(Slug.make(from: "Café résumé"), "cafe-resume")
    }

    func testWordLimit() {
        let long = (1...20).map { "word\($0)" }.joined(separator: " ")
        XCTAssertEqual(Slug.make(from: long)?.split(separator: "-").count, Slug.maxWords)
    }

    func testLengthLimit() {
        let slug = Slug.make(from: String(repeating: "abcdefghij ", count: 7))
        XCTAssertNotNil(slug)
        XCTAssertLessThanOrEqual(slug!.count, Slug.maxLength)
    }

    func testNothingUsableIsNil() {
        XCTAssertNil(Slug.make(from: "  --- ... !!! "))
        XCTAssertNil(Slug.make(from: ""))
    }
}

final class FileNamerTests: XCTestCase {

    func testFilenameWithoutDate() {
        XCTAssertEqual(FileNamer.filename(stem: "a-b", ext: "png", captureDate: Date(), keepDate: false), "a-b.png")
    }

    func testFilenameWithDate() {
        var c = DateComponents()
        c.year = 2026; c.month = 10; c.day = 1; c.hour = 14; c.minute = 4; c.second = 21
        let date = Calendar(identifier: .gregorian).date(from: c)!
        XCTAssertEqual(FileNamer.filename(stem: "a-b", ext: "png", captureDate: date, keepDate: true),
                       "a-b 2026-10-01 at 14.04.21.png")
    }

    func testCollisionGetsNumbered() {
        let taken: Set<String> = ["a.png", "a-2.png"]
        XCTAssertEqual(FileNamer.available("a.png", isTaken: taken.contains), "a-3.png")
    }

    func testFreeNameIsKept() {
        XCTAssertEqual(FileNamer.available("a.png", isTaken: { _ in false }), "a.png")
    }
}

final class ScreenshotMetadataTests: XCTestCase {

    func testRealValues() {
        // The values from a real selection capture on this Mac.
        let m = ScreenshotMetadata.make(typeName: "selection", rectValues: [2926, 1150, 835, 204])
        XCTAssertEqual(m.type, .selection)
        XCTAssertEqual(m.rect, CGRect(x: 2926, y: 1150, width: 835, height: 204))
    }

    func testUnknownTypeAndBadRect() {
        let m = ScreenshotMetadata.make(typeName: "somethingNew", rectValues: [1, 2])
        XCTAssertEqual(m.type, .other)
        XCTAssertNil(m.rect)
    }

    func testEmptyRectIsNil() {
        XCTAssertNil(ScreenshotMetadata.make(typeName: "window", rectValues: [0, 0, 0, 0]).rect)
    }
}

final class WindowPickerTests: XCTestCase {

    private func w(_ owner: String, _ r: CGRect, layer: Int = 0) -> WindowInfo {
        WindowInfo(ownerName: owner, ownerPID: 1, title: nil, bounds: r, layer: layer)
    }

    func testFrontmostCoveringWindowWins() {
        let rect = CGRect(x: 100, y: 100, width: 200, height: 100)
        let windows = [w("Safari", CGRect(x: 0, y: 0, width: 500, height: 500)),
                       w("Finder", CGRect(x: 0, y: 0, width: 1000, height: 1000))]
        XCTAssertEqual(WindowPicker.pick(for: rect, among: windows)?.ownerName, "Safari")
    }

    func testFullScreenDockIsIgnored() {
        // macOS 27: the Dock owns an invisible window over the whole screen, frontmost.
        let rect = CGRect(x: 100, y: 100, width: 200, height: 100)
        let windows = [w("Dock", CGRect(x: 0, y: 0, width: 2560, height: 1440)),
                       w("Ghostty", CGRect(x: 50, y: 50, width: 800, height: 600))]
        XCTAssertEqual(WindowPicker.pick(for: rect, among: windows)?.ownerName, "Ghostty")
    }

    func testNonZeroLayerIsIgnored() {
        let rect = CGRect(x: 0, y: 0, width: 100, height: 100)
        let windows = [w("Menu", rect, layer: 101), w("Notes", rect)]
        XCTAssertEqual(WindowPicker.pick(for: rect, among: windows)?.ownerName, "Notes")
    }

    func testLowCoverageIsNotAMatch() {
        let rect = CGRect(x: 0, y: 0, width: 100, height: 100)
        let windows = [w("Notes", CGRect(x: 80, y: 0, width: 100, height: 100))]  // covers 20%
        XCTAssertNil(WindowPicker.pick(for: rect, among: windows))
    }
}

final class RuleNamerTests: XCTestCase {

    func testAppThenSubstantialWords() {
        XCTAssertEqual(RuleNamer.name(appName: "Safari", recognisedText: "The Pull Request 48 for RememberMyWindow"),
                       "safari-pull-request-remembermywindow")
    }

    func testNoTextGivesAppOnly() {
        XCTAssertEqual(RuleNamer.name(appName: "Microsoft Teams", recognisedText: ""), "microsoft-teams")
    }

    func testNothingAtAllIsNil() {
        XCTAssertNil(RuleNamer.name(appName: nil, recognisedText: "a 1 2"))
    }
}

final class RenameHistoryTests: XCTestCase {

    func testNewestFirstCappedAndPersisted() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("nomen-history-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        var history = RenameHistory(fileURL: url)
        for i in 0..<(RenameHistory.capacity + 5) {
            history.add(RenameRecord(folder: "/f", originalName: "o\(i).png", newName: "n\(i).png",
                                     date: Date(), method: "rules"))
        }
        XCTAssertEqual(history.records.count, RenameHistory.capacity)
        XCTAssertEqual(history.records.first?.newName, "n\(RenameHistory.capacity + 4).png")
        let reloaded = RenameHistory(fileURL: url)
        XCTAssertEqual(reloaded.records.map(\.newName), history.records.map(\.newName))
    }
}
