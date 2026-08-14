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

    // MARK: - Variation % deviation

    func testSequenceSplitAllowedDeviation_tenPercentOfTenSeconds() {
        XCTAssertEqual(viewModel.sequenceSplitAllowedDeviation(for: 10, variationPercent: 10), 1)
    }

    func testSequenceSplitAllowedDeviation_clampsPercentRange() {
        XCTAssertEqual(viewModel.sequenceSplitAllowedDeviation(for: 10, variationPercent: 0), 0.1)
        XCTAssertEqual(viewModel.sequenceSplitAllowedDeviation(for: 10, variationPercent: 200), 20)
        XCTAssertEqual(viewModel.sequenceSplitAllowedDeviation(for: 10, variationPercent: 2000), 100)
    }

    // MARK: - Variation-based breaks (default 10%)

    func testFindSequenceBreaks_tenSecondCadence_splitsOnOneSecondLonger() {
        let base = Date(timeIntervalSince1970: 0)
        var files: [(url: URL, date: Date)] = (0..<4).map { i in
            (url: URL(fileURLWithPath: "/tmp/a\(i).jpg"), date: base.addingTimeInterval(Double(i) * 10))
        }
        // Gap of 11s (≥ 10% longer than 10s) starts a new sequence
        files.append((url: URL(fileURLWithPath: "/tmp/b0.jpg"), date: base.addingTimeInterval(30 + 11)))
        files.append((url: URL(fileURLWithPath: "/tmp/b1.jpg"), date: base.addingTimeInterval(30 + 21)))

        let breaks = viewModel.findSequenceBreaks(in: files, variationPercent: 10)
        XCTAssertEqual(breaks, [0, 4], "An 11s gap on a 10s cadence should start a new sequence at 10%")
    }

    func testFindSequenceBreaks_tenSecondCadence_splitsOnOneSecondShorter() {
        let base = Date(timeIntervalSince1970: 0)
        var files: [(url: URL, date: Date)] = (0..<4).map { i in
            (url: URL(fileURLWithPath: "/tmp/a\(i).jpg"), date: base.addingTimeInterval(Double(i) * 10))
        }
        // Gap of 9s (≥ 10% shorter than 10s) starts a new sequence
        files.append((url: URL(fileURLWithPath: "/tmp/b0.jpg"), date: base.addingTimeInterval(30 + 9)))
        files.append((url: URL(fileURLWithPath: "/tmp/b1.jpg"), date: base.addingTimeInterval(30 + 19)))

        let breaks = viewModel.findSequenceBreaks(in: files, variationPercent: 10)
        XCTAssertEqual(breaks, [0, 4], "A 9s gap on a 10s cadence should start a new sequence at 10%")
    }

    func testFindSequenceBreaks_tenSecondCadence_toleratesSubThresholdJitter() {
        let base = Date(timeIntervalSince1970: 0)
        var files: [(url: URL, date: Date)] = (0..<3).map { i in
            (url: URL(fileURLWithPath: "/tmp/\(i).jpg"), date: base.addingTimeInterval(Double(i) * 10))
        }
        // 10.5s is only 5% off a 10s cadence — under the 10% threshold
        files.append((url: URL(fileURLWithPath: "/tmp/3.jpg"), date: base.addingTimeInterval(20 + 10.5)))
        files.append((url: URL(fileURLWithPath: "/tmp/4.jpg"), date: base.addingTimeInterval(20 + 20.5)))

        let breaks = viewModel.findSequenceBreaks(in: files, variationPercent: 10)
        XCTAssertEqual(breaks, [0], "Sub-threshold jitter should stay one sequence")
    }

    func testFindSequenceBreaks_higherVariationPercent_toleratesLargerSwing() {
        let base = Date(timeIntervalSince1970: 0)
        var files: [(url: URL, date: Date)] = (0..<3).map { i in
            (url: URL(fileURLWithPath: "/tmp/\(i).jpg"), date: base.addingTimeInterval(Double(i) * 10))
        }
        // 12s is 20% off; at 25% variation it should stay together
        files.append((url: URL(fileURLWithPath: "/tmp/3.jpg"), date: base.addingTimeInterval(20 + 12)))
        files.append((url: URL(fileURLWithPath: "/tmp/4.jpg"), date: base.addingTimeInterval(20 + 22)))

        let breaks = viewModel.findSequenceBreaks(in: files, variationPercent: 25)
        XCTAssertEqual(breaks, [0], "A 20% swing should be allowed when Variation % is 25")
    }

    func testFindSequenceBreaks_newSequenceRecalculatesCadence() {
        let base = Date(timeIntervalSince1970: 0)
        // Eight frames at 10s, then eight at 30s. A global 10s cadence would treat every 30s
        // gap as a split and send those frames to Extras; the second shoot must get its own cadence.
        var files: [(url: URL, date: Date)] = (0..<8).map { i in
            (url: URL(fileURLWithPath: "/tmp/a\(i).jpg"), date: base.addingTimeInterval(Double(i) * 10))
        }
        let secondStart = 70.0 + 30.0
        for i in 0..<8 {
            files.append((
                url: URL(fileURLWithPath: "/tmp/b\(i).jpg"),
                date: base.addingTimeInterval(secondStart + Double(i) * 30)
            ))
        }

        let breaks = viewModel.findSequenceBreaks(in: files, variationPercent: 10)
        XCTAssertEqual(breaks, [0, 8], "A later 30s cadence should stay one sequence after splitting off 10s")
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
