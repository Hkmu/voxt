import Foundation
import AppKit
import Combine

@MainActor
final class AppUpdateManager: NSObject, ObservableObject, URLSessionDownloadDelegate {
    struct Manifest: Decodable {
        let version: String
        let minimumSupportedVersion: String?
        let downloadURL: String
        let releaseNotes: String?
        let publishedAt: String?
    }

    enum CheckSource {
        case automatic
        case manual
    }

    @Published private(set) var latestManifest: Manifest?
    @Published private(set) var hasUpdate = false
    @Published private(set) var isChecking = false
    @Published private(set) var isDownloading = false
    @Published private(set) var downloadProgress: Double = 0
    @Published private(set) var downloadedPackageURL: URL?
    @Published var showUpdateSheet = false
    @Published var statusMessage: String?

    private lazy var downloadSession: URLSession = {
        let configuration = URLSessionConfiguration.default
        return URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
    }()
    private var downloadTask: URLSessionDownloadTask?

    func checkForUpdates(source: CheckSource) async {
        guard !isChecking else { return }
        guard let manifestURL = updateManifestURL else {
            if source == .manual {
                statusMessage = AppLocalization.localizedString("Update manifest URL is not configured.")
                showUpdateSheet = true
            }
            return
        }

        isChecking = true
        defer { isChecking = false }

        do {
            let manifest = try await fetchManifest(from: manifestURL)
            guard let currentVersion else {
                if source == .manual {
                    statusMessage = AppLocalization.localizedString("Unable to read current app version.")
                    showUpdateSheet = true
                }
                return
            }

            if let minimum = manifest.minimumSupportedVersion,
               compareVersions(currentVersion, minimum) == .orderedAscending {
                hasUpdate = true
                latestManifest = manifest
                statusMessage = AppLocalization.localizedString("This version is no longer supported. Please install the latest version.")
                showUpdateSheet = true
                return
            }

            if compareVersions(currentVersion, manifest.version) == .orderedAscending {
                if skippedVersion == manifest.version {
                    hasUpdate = false
                    latestManifest = nil
                    downloadedPackageURL = nil
                    if source == .manual {
                        statusMessage = AppLocalization.format("Version %@ is skipped.", manifest.version)
                        showUpdateSheet = true
                    }
                    return
                }
                latestManifest = manifest
                hasUpdate = true
                statusMessage = nil
                if source == .manual {
                    showUpdateSheet = true
                }
            } else {
                hasUpdate = false
                latestManifest = nil
                downloadedPackageURL = nil
                if source == .manual {
                    statusMessage = AppLocalization.localizedString("You're Up to Date")
                    showUpdateSheet = true
                }
            }
        } catch {
            if source == .manual {
                statusMessage = AppLocalization.format("Failed to check updates: %@", error.localizedDescription)
                showUpdateSheet = true
            }
        }
    }

    func startDownload() {
        guard !isDownloading else { return }
        guard let manifest = latestManifest,
              let url = URL(string: manifest.downloadURL) else {
            statusMessage = AppLocalization.localizedString("Invalid update download URL.")
            showUpdateSheet = true
            return
        }

        statusMessage = nil
        isDownloading = true
        downloadProgress = 0
        downloadedPackageURL = nil

        let task = downloadSession.downloadTask(with: url)
        downloadTask = task
        task.resume()
    }

    func installAndRestart() {
        guard let packageURL = downloadedPackageURL else {
            statusMessage = AppLocalization.localizedString("Installer package not downloaded yet.")
            return
        }

        NSWorkspace.shared.open(packageURL)
        NSApp.terminate(nil)
    }

    func cancelDownload() {
        guard isDownloading else { return }
        downloadTask?.cancel()
        downloadTask = nil
        isDownloading = false
        downloadProgress = 0
    }

    var latestVersion: String? {
        latestManifest?.version
    }

    var canSkipLatestVersion: Bool {
        guard hasUpdate, latestManifest != nil, !isDownloading, downloadedPackageURL == nil else {
            return false
        }
        return true
    }

    func skipCurrentVersion() {
        guard let version = latestManifest?.version else { return }
        UserDefaults.standard.set(version, forKey: AppPreferenceKey.skippedUpdateVersion)
        hasUpdate = false
        latestManifest = nil
        downloadedPackageURL = nil
        isDownloading = false
        downloadProgress = 0
        statusMessage = AppLocalization.format("Skipped version %@.", version)
        showUpdateSheet = false
    }

    private var updateManifestURL: URL? {
        guard let raw = UserDefaults.standard.string(forKey: AppPreferenceKey.updateManifestURL),
              let url = URL(string: raw), !raw.isEmpty else {
            return nil
        }
        return url
    }

    private var currentVersion: String? {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
    }

    private var skippedVersion: String? {
        UserDefaults.standard.string(forKey: AppPreferenceKey.skippedUpdateVersion)
    }

    private func fetchManifest(from url: URL) async throws -> Manifest {
        let (data, response) = try await URLSession.shared.data(from: url)
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw URLError(.badServerResponse)
        }
        return try JSONDecoder().decode(Manifest.self, from: data)
    }

    private func compareVersions(_ lhs: String, _ rhs: String) -> ComparisonResult {
        let lhsParts = lhs.split(separator: ".").map { Int($0) ?? 0 }
        let rhsParts = rhs.split(separator: ".").map { Int($0) ?? 0 }
        let count = max(lhsParts.count, rhsParts.count)

        for index in 0..<count {
            let l = index < lhsParts.count ? lhsParts[index] : 0
            let r = index < rhsParts.count ? rhsParts[index] : 0
            if l < r { return .orderedAscending }
            if l > r { return .orderedDescending }
        }
        return .orderedSame
    }

    nonisolated func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        guard totalBytesExpectedToWrite > 0 else { return }
        let progress = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
        Task { @MainActor in
            self.downloadProgress = max(0, min(1, progress))
        }
    }

    nonisolated func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        Task { @MainActor in
            do {
                let fileManager = FileManager.default
                let downloadsDir = fileManager.urls(for: .downloadsDirectory, in: .userDomainMask).first
                    ?? fileManager.temporaryDirectory
                let version = self.latestManifest?.version ?? "latest"
                let destination = downloadsDir.appendingPathComponent("Voxt-\(version).pkg")
                if fileManager.fileExists(atPath: destination.path) {
                    try fileManager.removeItem(at: destination)
                }
                try fileManager.moveItem(at: location, to: destination)

                self.downloadedPackageURL = destination
                self.isDownloading = false
                self.downloadTask = nil
                self.downloadProgress = 1
                self.statusMessage = AppLocalization.localizedString("Download complete. Ready to install.")
            } catch {
                self.isDownloading = false
                self.downloadTask = nil
                self.downloadProgress = 0
                self.statusMessage = AppLocalization.format("Failed to save installer: %@", error.localizedDescription)
            }
        }
    }

    nonisolated func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didCompleteWithError error: Error?
    ) {
        guard let error else { return }
        Task { @MainActor in
            self.isDownloading = false
            self.downloadTask = nil
            self.downloadProgress = 0
            self.statusMessage = AppLocalization.format("Download failed: %@", error.localizedDescription)
        }
    }
}
