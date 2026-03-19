import Foundation
import AppKit
import HuggingFace

enum ModelStorageDirectoryManager {
    private static var securityScopedURL: URL?
    private static let fileManager = FileManager.default

    static var defaultRootURL: URL {
        HubCache.default.cacheDirectory
    }

    static func resolvedRootURL() -> URL {
        let defaults = UserDefaults.standard
        if let bookmarkData = defaults.data(forKey: AppPreferenceKey.modelStorageRootBookmark),
           let bookmarkedURL = resolveSecurityScopedURL(from: bookmarkData) {
            return bookmarkedURL
        }

        if let path = defaults.string(forKey: AppPreferenceKey.modelStorageRootPath), !path.isEmpty {
            return URL(fileURLWithPath: path, isDirectory: true)
        }

        return defaultRootURL
    }

    static func saveUserSelectedRootURL(_ url: URL) throws {
        let normalized = url.standardizedFileURL
        let bookmark = try normalized.bookmarkData(
            options: [.withSecurityScope],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )

        let defaults = UserDefaults.standard
        defaults.set(normalized.path, forKey: AppPreferenceKey.modelStorageRootPath)
        defaults.set(bookmark, forKey: AppPreferenceKey.modelStorageRootBookmark)

        _ = resolveSecurityScopedURL(from: bookmark)
    }

    static func openRootInFinder() {
        let url = resolvedRootURL()
        try? fileManager.createDirectory(at: url, withIntermediateDirectories: true)
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    private static func resolveSecurityScopedURL(from bookmarkData: Data) -> URL? {
        var isStale = false
        guard let resolved = try? URL(
            resolvingBookmarkData: bookmarkData,
            options: [.withSecurityScope, .withoutUI],
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        ) else {
            return nil
        }

        if securityScopedURL?.path != resolved.path {
            securityScopedURL?.stopAccessingSecurityScopedResource()
            if resolved.startAccessingSecurityScopedResource() {
                securityScopedURL = resolved
            }
        }

        if isStale,
           let refreshed = try? resolved.bookmarkData(
                options: [.withSecurityScope],
                includingResourceValuesForKeys: nil,
                relativeTo: nil
           ) {
            UserDefaults.standard.set(refreshed, forKey: AppPreferenceKey.modelStorageRootBookmark)
        }

        return resolved
    }
}
