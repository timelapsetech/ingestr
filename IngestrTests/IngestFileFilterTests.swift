import XCTest
@testable import Ingestr

final class IngestFileFilterTests: XCTestCase {
    var tempDir: URL!

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    func testShouldExclude_dotPathComponents() {
        let source = tempDir.appendingPathComponent("Source", isDirectory: true)
        let hidden = source.appendingPathComponent(".hidden/photo.jpg")
        XCTAssertTrue(IngestFileFilter.shouldExclude(url: hidden, relativeTo: source))
    }

    func testShouldExclude_macOSXFolder() {
        let source = tempDir.appendingPathComponent("Source", isDirectory: true)
        let resource = source.appendingPathComponent("__MACOSX/._photo.jpg")
        XCTAssertTrue(IngestFileFilter.shouldExclude(url: resource, relativeTo: source))
    }

    func testShouldExclude_appleDoublePrefix() {
        let source = tempDir.appendingPathComponent("Source", isDirectory: true)
        let appleDouble = source.appendingPathComponent("._IMG_0001.jpg")
        XCTAssertTrue(IngestFileFilter.shouldExclude(url: appleDouble, relativeTo: source))
    }

    func testShouldExclude_knownJunkNames() {
        let source = tempDir.appendingPathComponent("Source", isDirectory: true)
        XCTAssertTrue(IngestFileFilter.shouldExclude(url: source.appendingPathComponent(".DS_Store"), relativeTo: source))
        XCTAssertTrue(IngestFileFilter.shouldExclude(url: source.appendingPathComponent("Thumbs.db"), relativeTo: source))
        XCTAssertTrue(IngestFileFilter.shouldExclude(url: source.appendingPathComponent("desktop.ini"), relativeTo: source))
    }

    func testShouldExclude_allowsNormalImage() {
        let source = tempDir.appendingPathComponent("Source", isDirectory: true)
        let image = source.appendingPathComponent("Shoot/IMG_0001.jpg")
        XCTAssertFalse(IngestFileFilter.shouldExclude(url: image, relativeTo: source))
    }

    func testIsIngestible_requiresRegularFile() throws {
        let source = tempDir.appendingPathComponent("Source", isDirectory: true)
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        let subfolder = source.appendingPathComponent("Shoot", isDirectory: true)
        try FileManager.default.createDirectory(at: subfolder, withIntermediateDirectories: true)
        XCTAssertFalse(IngestFileFilter.isIngestible(url: subfolder, relativeTo: source, extensionFilter: ""))
    }

    func testIsIngestible_respectsExtensionFilter() throws {
        let source = tempDir.appendingPathComponent("Source", isDirectory: true)
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        let jpg = source.appendingPathComponent("a.jpg")
        let raw = source.appendingPathComponent("b.cr2")
        FileManager.default.createFile(atPath: jpg.path, contents: Data([0x01]))
        FileManager.default.createFile(atPath: raw.path, contents: Data([0x02]))
        XCTAssertTrue(IngestFileFilter.isIngestible(url: jpg, relativeTo: source, extensionFilter: "jpg"))
        XCTAssertFalse(IngestFileFilter.isIngestible(url: raw, relativeTo: source, extensionFilter: "jpg"))
    }
}
