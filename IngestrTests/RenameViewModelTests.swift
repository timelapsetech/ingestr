import XCTest
@testable import Ingestr

class RenameViewModelTests: XCTestCase {
    var tempDir: URL!
    var fileManager: FileManager!
    var viewModel: RenameViewModel!

    override func setUpWithError() throws {
        fileManager = FileManager.default
        tempDir = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try fileManager.createDirectory(at: tempDir, withIntermediateDirectories: true)
        viewModel = RenameViewModel()
    }

    override func tearDownWithError() throws {
        try? fileManager.removeItem(at: tempDir)
        tempDir = nil
        viewModel = nil
    }

    func createFiles(_ names: [String], in dir: URL) {
        for name in names {
            let fileURL = dir.appendingPathComponent(name)
            fileManager.createFile(atPath: fileURL.path, contents: Data())
        }
    }

    func testFindLastSequenceNumber_basic() {
        let baseName = "200704161CO_"
        createFiles(["200704161CO_0001.jpg", "200704161CO_0002.jpg", "200704161CO_0100.jpg"], in: tempDir)
        let result = viewModel.findLastSequenceNumber(in: tempDir, baseName: baseName)
        XCTAssertEqual(result?.lastNumber, 100)
        XCTAssertEqual(result?.padding, 4)
    }

    func testFindLastSequenceNumber_noMatches() {
        let baseName = "200704161CO_"
        createFiles(["IMG_0001.jpg", "IMG_0002.jpg"], in: tempDir)
        let result = viewModel.findLastSequenceNumber(in: tempDir, baseName: baseName)
        XCTAssertNil(result)
    }

    func testFindLastSequenceNumber_variedPadding() {
        let baseName = "200704161CO_"
        createFiles(["200704161CO_01.jpg", "200704161CO_002.jpg", "200704161CO_0003.jpg"], in: tempDir)
        let result = viewModel.findLastSequenceNumber(in: tempDir, baseName: baseName)
        XCTAssertEqual(result?.lastNumber, 3)
        XCTAssertEqual(result?.padding, 4)
    }

    func testFindLastSequenceNumber_missingUnderscore() {
        let baseName = "200704161CO_"
        createFiles(["200704161CO0001.jpg", "200704161CO_0002.jpg"], in: tempDir)
        let result = viewModel.findLastSequenceNumber(in: tempDir, baseName: baseName)
        XCTAssertEqual(result?.lastNumber, 2)
        XCTAssertEqual(result?.padding, 4)
    }

    func testFilenameGeneration_withUnderscore() {
        viewModel.basename = "200704161CO_"
        let dummyURL = URL(fileURLWithPath: "dummy.jpg")
        let filename = viewModel.generateNewSequentialName(currentNumber: 101, fileURL: dummyURL)
        XCTAssertEqual(filename, "200704161CO_0101.jpg")
    }

    func testFilenameGeneration_withoutUnderscore() {
        viewModel.basename = "IMG_"
        let dummyURL = URL(fileURLWithPath: "dummy.jpg")
        let filename = viewModel.generateNewSequentialName(currentNumber: 5, fileURL: dummyURL)
        XCTAssertEqual(filename, "IMG_0005.jpg")
    }

    func testFindLastSequenceNumber_differentExtensions() {
        let baseName = "200704161CO_"
        createFiles(["200704161CO_0001.jpg", "200704161CO_0002.png", "200704161CO_0003.tif"], in: tempDir)
        let result = viewModel.findLastSequenceNumber(in: tempDir, baseName: baseName)
        XCTAssertEqual(result?.lastNumber, 3)
        XCTAssertEqual(result?.padding, 4)
    }

    func testFindLastSequenceNumber_nonSequentialFiles() {
        let baseName = "200704161CO_"
        createFiles(["200704161CO_0001.jpg", "randomfile.txt", "IMG_0002.jpg"], in: tempDir)
        let result = viewModel.findLastSequenceNumber(in: tempDir, baseName: baseName)
        XCTAssertEqual(result?.lastNumber, 1)
        XCTAssertEqual(result?.padding, 4)
    }

    // You can add more tests for processSequence and other logic by exposing them as internal or using @testable import
} 