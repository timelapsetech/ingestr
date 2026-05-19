import Foundation

/// Persists user-selected directories as security-scoped bookmarks for App Sandbox access.
enum DirectoryBookmark {
    private static let pathSuffix = ".path"

    /// Call when the user picks or drops a folder so the sandbox grant is captured in a bookmark.
    static func captureUserSelectedDirectory(_ url: URL, key: String) {
        _ = url.startAccessingSecurityScopedResource()
        store(url, key: key)
    }

    static func store(_ url: URL, key: String) {
        do {
            let data = try url.bookmarkData(
                options: .withSecurityScope,
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
            UserDefaults.standard.set(data, forKey: key)
            UserDefaults.standard.set(url.path, forKey: key + pathSuffix)
        } catch {
            print("DirectoryBookmark: failed to store bookmark for \(url.path): \(error)")
            UserDefaults.standard.set(url.path, forKey: key + pathSuffix)
        }
    }

    /// Prefer a resolved security-scoped bookmark over a plain path saved in settings.
    static func resolve(stored: URL?, key: String) -> URL? {
        if let bookmarked = restore(key: key) {
            return bookmarked
        }
        return stored
    }

    static func restore(key: String) -> URL? {
        if let data = UserDefaults.standard.data(forKey: key) {
            var stale = false
            do {
                let url = try URL(
                    resolvingBookmarkData: data,
                    options: .withSecurityScope,
                    relativeTo: nil,
                    bookmarkDataIsStale: &stale
                )
                if stale {
                    store(url, key: key)
                }
                return url
            } catch {
                print("DirectoryBookmark: failed to resolve bookmark for \(key): \(error)")
            }
        }
        if let path = UserDefaults.standard.string(forKey: key + pathSuffix) {
            return URL(fileURLWithPath: path)
        }
        return nil
    }

    static func clear(key: String) {
        UserDefaults.standard.removeObject(forKey: key)
        UserDefaults.standard.removeObject(forKey: key + pathSuffix)
    }

    static func beginAccess(to url: URL) -> Bool {
        url.startAccessingSecurityScopedResource()
    }

    /// Verifies the app can create folders under the output directory (sandbox write grant).
    static func verifyCanWrite(to outputRoot: URL) throws {
        let fileManager = FileManager.default
        let probeDir = outputRoot.appendingPathComponent(".ingestr-write-test", isDirectory: true)
        do {
            try fileManager.createDirectory(at: probeDir, withIntermediateDirectories: false)
            try fileManager.removeItem(at: probeDir)
        } catch {
            throw IngestFilesystemError.outputAccessDenied(outputRoot)
        }
    }

    static func createDirectory(
        at url: URL,
        outputRoot: URL,
        label: String
    ) throws {
        do {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        } catch {
            throw IngestFilesystemError.cannotCreateDirectory(
                attempted: url,
                outputRoot: outputRoot,
                label: label,
                underlying: error
            )
        }
    }
}
