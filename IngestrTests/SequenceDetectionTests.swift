import XCTest
@testable import Ingestr

final class SequenceDetectionTests: XCTestCase {
    var viewModel: RenameViewModel!
    var tempDir: URL!
    var fileManager: FileManager!

    override func setUpWithError() throws {
        viewModel = RenameViewModel()
        fileManager = FileManager.default
        tempDir = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try fileManager.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? fileManager.removeItem(at: tempDir)
    }

    // MARK: - Sequence folder index parsing

    func testParseSequenceIndex_singleAndMultiDigit() {
        XCTAssertEqual(viewModel.parseSequenceIndex(fromFolderName: "202505041CO", datePrefix: "20250504"), 1)
        XCTAssertEqual(viewModel.parseSequenceIndex(fromFolderName: "2025050410CO", datePrefix: "20250504"), 10)
        XCTAssertEqual(viewModel.parseSequenceIndex(fromFolderName: "2025050412CO", datePrefix: "20250504"), 12)
        XCTAssertNil(viewModel.parseSequenceIndex(fromFolderName: "20250504CO", datePrefix: "20250504"))
        XCTAssertNil(viewModel.parseSequenceIndex(fromFolderName: "20250504XCO", datePrefix: "20250504"))
    }

    // MARK: - Source folder grouping

    func testSourceRelativeGroupKey_nestedShootFolders() {
        let source = tempDir.appendingPathComponent("Source")
        let shootA = source.appendingPathComponent("ShootA/IMG_001.jpg")
        let shootB = source.appendingPathComponent("ShootB/sub/IMG_002.jpg")
        let rootFile = source.appendingPathComponent("IMG_000.jpg")

        XCTAssertEqual(viewModel.sourceRelativeGroupKey(for: shootA, sourceRoot: source), "ShootA")
        XCTAssertEqual(viewModel.sourceRelativeGroupKey(for: shootB, sourceRoot: source), "ShootB/sub")
        XCTAssertEqual(viewModel.sourceRelativeGroupKey(for: rootFile, sourceRoot: source), "")
    }

    func testGroupFilesBySourceFolder_splitsShoots() {
        let source = tempDir.appendingPathComponent("Source")
        let fileA = (url: source.appendingPathComponent("A/a.jpg"), date: Date(timeIntervalSince1970: 100))
        let fileB = (url: source.appendingPathComponent("B/b.jpg"), date: Date(timeIntervalSince1970: 200))
        let groups = viewModel.groupFilesBySourceFolder([fileA, fileB], sourceRoot: source)

        XCTAssertEqual(groups.count, 2)
        XCTAssertEqual(groups["A"]?.count, 1)
        XCTAssertEqual(groups["B"]?.count, 1)
    }

    // MARK: - Split threshold tiers

    func testSequenceSplitThreshold_fastTimelapseRequiresTenMinuteGap() {
        XCTAssertEqual(viewModel.sequenceSplitThreshold(for: 5), 600)
        XCTAssertEqual(viewModel.sequenceSplitThreshold(for: 30), 600)
    }

    func testSequenceSplitThreshold_mediumCadenceUsesAdaptiveFloor() {
        XCTAssertEqual(viewModel.sequenceSplitThreshold(for: 60), 300)
        XCTAssertEqual(viewModel.sequenceSplitThreshold(for: 120), 600)
    }

    // MARK: - Fast timelapse (3–30s cadence)

    func testFindSequenceBreaks_fastTimelapse_toleratesTwoMinutePause() {
        let base = Date(timeIntervalSince1970: 0)
        let files: [(url: URL, date: Date)] = (0..<5).map { i in
            (url: URL(fileURLWithPath: "/tmp/\(i).jpg"), date: base.addingTimeInterval(Double(i) * 5))
        }
        var withPause = files
        withPause.append((url: URL(fileURLWithPath: "/tmp/5.jpg"), date: base.addingTimeInterval(120)))
        withPause.append((url: URL(fileURLWithPath: "/tmp/6.jpg"), date: base.addingTimeInterval(125)))

        let breaks = viewModel.findSequenceBreaks(in: withPause, normalInterval: 5)
        XCTAssertEqual(breaks, [0], "A 2-minute pause on a 5s timelapse should stay one sequence")
    }

    func testFindSequenceBreaks_fastTimelapse_splitsAfterTenMinutes() {
        let base = Date(timeIntervalSince1970: 0)
        var files: [(url: URL, date: Date)] = (0..<5).map { i in
            (url: URL(fileURLWithPath: "/tmp/a\(i).jpg"), date: base.addingTimeInterval(Double(i) * 5))
        }
        files.append((url: URL(fileURLWithPath: "/tmp/b0.jpg"), date: base.addingTimeInterval(660)))
        files.append((url: URL(fileURLWithPath: "/tmp/b1.jpg"), date: base.addingTimeInterval(665)))

        let breaks = viewModel.findSequenceBreaks(in: files, normalInterval: 5)
        XCTAssertEqual(breaks, [0, 5], "An 11-minute gap should start a new sequence")
    }

    func testFindSequenceBreaks_fastTimelapse_splitsExactlyAtTenMinutes() {
        let base = Date(timeIntervalSince1970: 0)
        var files: [(url: URL, date: Date)] = (0..<3).map { i in
            (url: URL(fileURLWithPath: "/tmp/a\(i).jpg"), date: base.addingTimeInterval(Double(i) * 3))
        }
        files.append((url: URL(fileURLWithPath: "/tmp/b0.jpg"), date: base.addingTimeInterval(9 + 600)))
        files.append((url: URL(fileURLWithPath: "/tmp/b1.jpg"), date: base.addingTimeInterval(9 + 603)))

        let breaks = viewModel.findSequenceBreaks(in: files, normalInterval: 3)
        XCTAssertEqual(breaks, [0, 3], "A 10-minute gap should start a new sequence")
    }

    // MARK: - Medium cadence (~30–120s between frames)

    func testFindSequenceBreaks_sixtySecondCadence_toleratesTwoMinutePause() {
        let base = Date(timeIntervalSince1970: 0)
        var files: [(url: URL, date: Date)] = (0..<4).map { i in
            (url: URL(fileURLWithPath: "/tmp/\(i).jpg"), date: base.addingTimeInterval(Double(i) * 60))
        }
        files.append((url: URL(fileURLWithPath: "/tmp/4.jpg"), date: base.addingTimeInterval(240 + 120)))
        files.append((url: URL(fileURLWithPath: "/tmp/5.jpg"), date: base.addingTimeInterval(240 + 180)))

        let breaks = viewModel.findSequenceBreaks(in: files, normalInterval: 60)
        XCTAssertEqual(breaks, [0], "A 2-minute extra pause on 60s cadence should stay one sequence")
    }

    func testFindSequenceBreaks_sixtySecondCadence_splitsOnFiveMinuteSessionGap() {
        let base = Date(timeIntervalSince1970: 0)
        var files: [(url: URL, date: Date)] = (0..<4).map { i in
            (url: URL(fileURLWithPath: "/tmp/a\(i).jpg"), date: base.addingTimeInterval(Double(i) * 60))
        }
        files.append((url: URL(fileURLWithPath: "/tmp/b0.jpg"), date: base.addingTimeInterval(240 + 300)))
        files.append((url: URL(fileURLWithPath: "/tmp/b1.jpg"), date: base.addingTimeInterval(240 + 360)))

        let breaks = viewModel.findSequenceBreaks(in: files, normalInterval: 60)
        XCTAssertEqual(breaks, [0, 4], "A 5-minute gap on 60s cadence should start a new sequence")
    }

    // MARK: - Cadence detection

    func testDetectNormalInterval_ignoresSessionGaps() {
        let base = Date(timeIntervalSince1970: 0)
        var files: [(url: URL, date: Date)] = (0..<4).map { i in
            (url: URL(fileURLWithPath: "/tmp/\(i).jpg"), date: base.addingTimeInterval(Double(i) * 10))
        }
        files.append((url: URL(fileURLWithPath: "/tmp/4.jpg"), date: base.addingTimeInterval(3600)))

        XCTAssertEqual(viewModel.detectNormalInterval(in: files), 10)
    }

    func testDetectNormalInterval_includesUpToThreeMinuteSpacing() {
        let base = Date(timeIntervalSince1970: 0)
        let files: [(url: URL, date: Date)] = (0..<5).map { i in
            (url: URL(fileURLWithPath: "/tmp/\(i).jpg"), date: base.addingTimeInterval(Double(i) * 90))
        }
        XCTAssertEqual(viewModel.detectNormalInterval(in: files), 90)
    }

    func testDetectNormalInterval_usesHundredTwentySecondCadence() {
        let base = Date(timeIntervalSince1970: 0)
        let files: [(url: URL, date: Date)] = (0..<4).map { i in
            (url: URL(fileURLWithPath: "/tmp/\(i).jpg"), date: base.addingTimeInterval(Double(i) * 120))
        }
        XCTAssertEqual(viewModel.detectNormalInterval(in: files), 120)
    }
}
