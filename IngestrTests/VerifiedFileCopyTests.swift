import XCTest
@testable import Ingestr

final class VerifiedFileCopyTests: XCTestCase {
    var tempDir: URL!

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let tempDir {
            try? FileManager.default.removeItem(at: tempDir)
        }
        tempDir = nil
    }

    func testNone_copiesIdentically() async throws {
        let src = tempDir.appendingPathComponent("source.bin")
        let dst = tempDir.appendingPathComponent("dest.bin")
        let data = Data((0..<4096).map { UInt8($0 % 256) })
        try data.write(to: src)
        try await VerifiedFileCopy.copyWithVerification(from: src, to: dst, mode: .none)
        XCTAssertEqual(try Data(contentsOf: src), try Data(contentsOf: dst))
    }

    func testFull_copiesIdentically() async throws {
        let src = tempDir.appendingPathComponent("source.bin")
        let dst = tempDir.appendingPathComponent("dest.bin")
        let data = Data((0..<9000).map { UInt8($0 % 251) })
        try data.write(to: src)
        try await VerifiedFileCopy.copyWithVerification(from: src, to: dst, mode: .full)
        XCTAssertEqual(try Data(contentsOf: src), try Data(contentsOf: dst))
    }

    func testSizeOnly_copiesIdentically() async throws {
        let src = tempDir.appendingPathComponent("source.bin")
        let dst = tempDir.appendingPathComponent("dest.bin")
        let data = Data("hello-size-only".utf8)
        try data.write(to: src)
        try await VerifiedFileCopy.copyWithVerification(from: src, to: dst, mode: .sizeOnly)
        XCTAssertEqual(try Data(contentsOf: src), try Data(contentsOf: dst))
    }

    func testFull_preservesCreationAndModificationDates() async throws {
        let src = tempDir.appendingPathComponent("dated.bin")
        let dst = tempDir.appendingPathComponent("dated-out.bin")
        try Data([0xAB, 0xCD]).write(to: src)
        let created = Date(timeIntervalSince1970: 1_500_000_000)
        let modified = Date(timeIntervalSince1970: 1_600_000_000)
        try FileManager.default.setAttributes(
            [.creationDate: created, .modificationDate: modified],
            ofItemAtPath: src.path
        )

        try await VerifiedFileCopy.copyWithVerification(from: src, to: dst, mode: .full)

        let values = try dst.resourceValues(forKeys: [.creationDateKey, .contentModificationDateKey])
        XCTAssertEqual(values.creationDate?.timeIntervalSince1970 ?? 0, created.timeIntervalSince1970, accuracy: 1)
        XCTAssertEqual(values.contentModificationDate?.timeIntervalSince1970 ?? 0, modified.timeIntervalSince1970, accuracy: 1)
    }

    func testNone_preservesCreationAndModificationDates() async throws {
        let src = tempDir.appendingPathComponent("dated-none.bin")
        let dst = tempDir.appendingPathComponent("dated-none-out.bin")
        try Data([1, 2, 3]).write(to: src)
        let created = Date(timeIntervalSince1970: 1_700_000_000)
        let modified = Date(timeIntervalSince1970: 1_800_000_000)
        try FileManager.default.setAttributes(
            [.creationDate: created, .modificationDate: modified],
            ofItemAtPath: src.path
        )

        try await VerifiedFileCopy.copyWithVerification(from: src, to: dst, mode: .none)

        let values = try dst.resourceValues(forKeys: [.creationDateKey, .contentModificationDateKey])
        XCTAssertEqual(values.creationDate?.timeIntervalSince1970 ?? 0, created.timeIntervalSince1970, accuracy: 1)
        XCTAssertEqual(values.contentModificationDate?.timeIntervalSince1970 ?? 0, modified.timeIntervalSince1970, accuracy: 1)
    }

    func testPreserveFileMetadata_copiesExtendedAttribute() throws {
        let src = tempDir.appendingPathComponent("xattr-src.bin")
        let dst = tempDir.appendingPathComponent("xattr-dst.bin")
        try Data("x".utf8).write(to: src)
        try Data().write(to: dst)
        let attrName = "com.ingestr.test"
        let attrValue: [UInt8] = [9, 8, 7]
        try attrValue.withUnsafeBytes { raw in
            guard setxattr(src.path, attrName, raw.baseAddress, attrValue.count, 0, 0) == 0 else {
                XCTFail("setxattr on source failed")
                return
            }
        }

        try VerifiedFileCopy.preserveFileMetadata(from: src, to: dst)

        var readLength = getxattr(dst.path, attrName, nil, 0, 0, 0)
        XCTAssertEqual(readLength, attrValue.count)
        var readValue = [UInt8](repeating: 0, count: readLength)
        XCTAssertEqual(getxattr(dst.path, attrName, &readValue, readLength, 0, 0), readLength)
        XCTAssertEqual(readValue, attrValue)
    }

    func testVerifySizeOnlyAfterCopy_removesDestOnMismatch() async throws {
        let src = tempDir.appendingPathComponent("a.bin")
        let dst = tempDir.appendingPathComponent("b.bin")
        try Data(repeating: 1, count: 100).write(to: src)
        try Data(repeating: 2, count: 40).write(to: dst)
        do {
            try await VerifiedFileCopy.verifySizeOnlyAfterCopy(source: src, destination: dst)
            XCTFail("expected mismatch error")
        } catch {
            XCTAssertNotNil(error as? VerifiedFileCopyError)
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: dst.path))
    }
}
