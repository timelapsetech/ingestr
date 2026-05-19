import Foundation

/// Rules for skipping system and junk files during source enumeration.
enum IngestFileFilter {
    private static let junkFileNames: Set<String> = [
        ".ds_store",
        "thumbs.db",
        "desktop.ini",
    ]

    /// True when the file should not be ingested (hidden junk, sidecars, system metadata).
    static func shouldExclude(url: URL, relativeTo sourceRoot: URL) -> Bool {
        let filename = url.lastPathComponent

        if filename.hasPrefix("._") {
            return true
        }

        if junkFileNames.contains(filename.lowercased()) {
            return true
        }

        for component in pathComponents(from: url, relativeTo: sourceRoot) {
            if component.hasPrefix(".") {
                return true
            }
            if component == "__MACOSX" {
                return true
            }
        }

        return false
    }

    static func isIngestible(
        url: URL,
        relativeTo sourceRoot: URL,
        extensionFilter: String
    ) -> Bool {
        if shouldExclude(url: url, relativeTo: sourceRoot) {
            return false
        }

        do {
            let resourceValues = try url.resourceValues(forKeys: [.isRegularFileKey])
            guard let isRegularFile = resourceValues.isRegularFile, isRegularFile else {
                return false
            }
        } catch {
            return false
        }

        if extensionFilter.isEmpty {
            return true
        }

        return url.pathExtension.lowercased() == extensionFilter.lowercased()
    }

    private static func pathComponents(from fileURL: URL, relativeTo sourceRoot: URL) -> [String] {
        let rootPath = sourceRoot.standardizedFileURL.path
        let filePath = fileURL.standardizedFileURL.path
        guard filePath.hasPrefix(rootPath) else {
            return [fileURL.lastPathComponent]
        }
        var relative = String(filePath.dropFirst(rootPath.count))
        if relative.hasPrefix("/") {
            relative = String(relative.dropFirst())
        }
        guard !relative.isEmpty else { return [] }
        return relative.split(separator: "/").map(String.init)
    }
}
