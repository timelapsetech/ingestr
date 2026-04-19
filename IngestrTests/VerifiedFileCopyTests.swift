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
