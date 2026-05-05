import CryptoKit
import Foundation

enum VerifiedFileCopyError: LocalizedError {
    case digestMismatch(source: URL, destination: URL)
    case sizeMismatch(source: URL, destination: URL, sourceBytes: Int64, destBytes: Int64)

    var errorDescription: String? {
        switch self {
        case .digestMismatch(let source, let destination):
            return "Copy verification failed: byte content did not match between “\(source.path)” and “\(destination.path)”."
        case .sizeMismatch(let source, let destination, let sourceBytes, let destBytes):
            return "Copy verification failed: size \(sourceBytes) bytes vs \(destBytes) bytes between “\(source.path)” and “\(destination.path)”."
        }
    }
}

enum VerifiedFileCopy {
    private static let chunkSize = 1_048_576 // 1 MiB

    /// Copies `source` to `destination` according to `mode`. Parent directory of `destination` must exist.
    static func copyWithVerification(
        from source: URL,
        to destination: URL,
        mode: CopyVerificationMode
    ) async throws {
        switch mode {
        case .none:
            try FileManager.default.copyItem(at: source, to: destination)
        case .sizeOnly:
            try FileManager.default.copyItem(at: source, to: destination)
            try await verifySizeOnlyAfterCopy(source: source, destination: destination)
        case .full:
            try await copyStreamingSHA256(from: source, to: destination)
        }
    }

    private static func fileByteCount(at url: URL) throws -> Int64 {
        let values = try url.resourceValues(forKeys: [.fileSizeKey])
        return Int64(values.fileSize ?? 0)
    }

    /// Exposed for tests (`@testable import`).
    static func verifySizeOnlyAfterCopy(source: URL, destination: URL) async throws {
        if Task.isCancelled {
            try? FileManager.default.removeItem(at: destination)
            throw CancellationError()
        }
        let srcSize = try fileByteCount(at: source)
        let dstSize = try fileByteCount(at: destination)
        if srcSize != dstSize {
            try? FileManager.default.removeItem(at: destination)
            throw VerifiedFileCopyError.sizeMismatch(
                source: source,
                destination: destination,
                sourceBytes: srcSize,
                destBytes: dstSize
            )
        }
    }

    private static func copyStreamingSHA256(from source: URL, to destination: URL) async throws {
        let fm = FileManager.default
        if fm.fileExists(atPath: destination.path) {
            try fm.removeItem(at: destination)
        }
        guard fm.createFile(atPath: destination.path, contents: nil) else {
            throw CocoaError(.fileWriteUnknown)
        }

        guard let srcHandle = try? FileHandle(forReadingFrom: source) else {
            throw CocoaError(.fileReadUnknown)
        }
        defer {
            try? srcHandle.close()
        }

        guard let dstHandle = try? FileHandle(forWritingTo: destination) else {
            try? fm.removeItem(at: destination)
            throw CocoaError(.fileWriteUnknown)
        }
        defer {
            try? dstHandle.close()
        }

        var hasher = SHA256()
        var chunkIndex = 0
        while true {
            if Task.isCancelled {
                try? fm.removeItem(at: destination)
                throw CancellationError()
            }
            let chunk = try srcHandle.read(upToCount: chunkSize) ?? Data()
            if chunk.isEmpty { break }
            hasher.update(data: chunk)
            try dstHandle.write(contentsOf: chunk)
            chunkIndex += 1
            // Cooperate with the runtime so long copies don’t starve the main thread / UI updates.
            if chunkIndex.isMultiple(of: 32) {
                await Task.yield()
            }
        }
        try dstHandle.synchronize()

        let expectedDigest = hasher.finalize()

        var destHasher = SHA256()
        let verifyHandle = try FileHandle(forReadingFrom: destination)
        defer {
            try? verifyHandle.close()
        }
        var verifyChunkIndex = 0
        while true {
            if Task.isCancelled {
                try? fm.removeItem(at: destination)
                throw CancellationError()
            }
            let chunk = try verifyHandle.read(upToCount: chunkSize) ?? Data()
            if chunk.isEmpty { break }
            destHasher.update(data: chunk)
            verifyChunkIndex += 1
            if verifyChunkIndex.isMultiple(of: 32) {
                await Task.yield()
            }
        }
        let actualDigest = destHasher.finalize()
        if actualDigest != expectedDigest {
            try? fm.removeItem(at: destination)
            throw VerifiedFileCopyError.digestMismatch(source: source, destination: destination)
        }
    }
}
