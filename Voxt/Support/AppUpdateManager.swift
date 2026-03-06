import Foundation
import Sparkle
import AppKit

@MainActor
final class AppUpdateManager: NSObject, SPUStandardUserDriverDelegate, SPUUpdaterDelegate {
    enum CheckSource {
        case automatic
        case manual
    }

    private lazy var updaterController: SPUStandardUpdaterController = {
        SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: self,
            userDriverDelegate: self
        )
    }()

    private let stableFeedURLString = "https://voxt.actnow.dev/updates/stable/appcast.xml"
    private let betaFeedURLString = "https://voxt.actnow.dev/updates/beta/appcast.xml"
    private var lastCheckSource: CheckSource = .automatic
    private(set) var hasUpdate = false
    private(set) var latestVersion: String?

    // Background/dockless apps should opt into Sparkle's gentle reminder support
    // to avoid missing scheduled update alerts.
    var supportsGentleScheduledUpdateReminders: Bool { true }

    var automaticallyChecksForUpdates: Bool {
        get { updaterController.updater.automaticallyChecksForUpdates }
        set { updaterController.updater.automaticallyChecksForUpdates = newValue }
    }

    func checkForUpdates(source: CheckSource) {
        lastCheckSource = source
        if source == .manual {
            logInstallerServiceAvailability()
        }
        switch source {
        case .manual:
            VoxtLog.info("Manual update check triggered via Sparkle.")
            updaterController.checkForUpdates(nil)
        case .automatic:
            VoxtLog.info("Background update check triggered via Sparkle.")
            updaterController.updater.checkForUpdatesInBackground()
        }
    }

    func feedURLString(for updater: SPUUpdater) -> String? {
        selectedFeedURLString
    }

    func updater(_ updater: SPUUpdater, didAbortWithError error: any Error) {
        let nsError = error as NSError
        VoxtLog.error(
            """
            Sparkle update aborted. domain=\(nsError.domain), code=\(nsError.code), \
            description=\(nsError.localizedDescription), userInfo=\(nsError.userInfo)
            """
        )
        handleInstallerAuthorizationFailureIfNeeded(nsError)
    }

    func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        hasUpdate = true
        latestVersion = "\(item.displayVersionString) (\(item.versionString))"
        NotificationCenter.default.post(name: .voxtUpdateAvailabilityDidChange, object: nil)
        VoxtLog.info(
            """
            Sparkle found update. source=\(lastCheckSource.description), \
            version=\(item.displayVersionString), build=\(item.versionString), \
            minSystemVersion=\(item.minimumSystemVersion ?? "nil")
            """
        )
    }

    func updaterDidNotFindUpdate(_ updater: SPUUpdater, error: any Error) {
        hasUpdate = false
        latestVersion = nil
        NotificationCenter.default.post(name: .voxtUpdateAvailabilityDidChange, object: nil)
        let nsError = error as NSError
        VoxtLog.info(
            """
            Sparkle did not find update. source=\(lastCheckSource.description), \
            domain=\(nsError.domain), code=\(nsError.code), description=\(nsError.localizedDescription)
            """
        )
    }

    func updater(_ updater: SPUUpdater, didDownloadUpdate item: SUAppcastItem) {
        VoxtLog.info(
            """
            Sparkle finished downloading update. version=\(item.displayVersionString), \
            build=\(item.versionString), fileURL=\(item.fileURL?.absoluteString ?? "nil")
            """
        )
    }

    func updater(_ updater: SPUUpdater, failedToDownloadUpdate item: SUAppcastItem, error: any Error) {
        let nsError = error as NSError
        VoxtLog.error(
            """
            Sparkle failed to download update. version=\(item.displayVersionString), \
            build=\(item.versionString), domain=\(nsError.domain), \
            code=\(nsError.code), description=\(nsError.localizedDescription)
            """
        )
    }

    func updater(_ updater: SPUUpdater, didFinishUpdateCycleFor updateCheck: SPUUpdateCheck, error: (any Error)?) {
        if let error {
            let nsError = error as NSError
            VoxtLog.warning(
                """
                Sparkle finished update cycle with error. source=\(lastCheckSource.description), \
                check=\(String(describing: updateCheck)), domain=\(nsError.domain), \
                code=\(nsError.code), description=\(nsError.localizedDescription)
                """
            )
        } else {
            VoxtLog.info(
                "Sparkle finished update cycle successfully. source=\(lastCheckSource.description), check=\(String(describing: updateCheck))"
            )
        }
    }

    func standardUserDriverWillShowModalAlert() {
        VoxtLog.info("Sparkle will show modal alert.")
    }

    func standardUserDriverDidShowModalAlert() {
        VoxtLog.info("Sparkle did show modal alert.")
    }

    private var selectedFeedURLString: String {
        // Prefer stable feed by default. Beta feed should be explicitly opted in
        // because local/dev beta channels may contain test-only appcast entries.
        if let channel = ProcessInfo.processInfo.environment["VOXT_UPDATE_CHANNEL"]?.lowercased() {
            switch channel {
            case "beta":
                return betaFeedURLString
            case "stable":
                return stableFeedURLString
            default:
                break
            }
        }
        return stableFeedURLString
    }

    private func handleInstallerAuthorizationFailureIfNeeded(_ error: NSError) {
        let message = error.localizedDescription.lowercased()
        let indicatesInstallerAuthFailure =
            message.contains("authorization") ||
            message.contains("installer") ||
            message.contains("gain authorization required to update target")
        guard indicatesInstallerAuthFailure else { return }

        let manualDownloadURL = selectedFeedURLString
            .replacingOccurrences(of: "/appcast.xml", with: "/")

        guard let url = URL(string: manualDownloadURL) else { return }
        VoxtLog.warning("Sparkle installer authorization failed. Opening manual download page: \(manualDownloadURL)")
        NSWorkspace.shared.open(url)
    }

    private func logInstallerServiceAvailability() {
        let appXPCServicesURL = Bundle.main.bundleURL.appendingPathComponent("Contents/XPCServices", isDirectory: true)
        let frameworkXPCServicesURL = Bundle.main.bundleURL
            .appendingPathComponent("Contents/Frameworks/Sparkle.framework/Versions/B/XPCServices", isDirectory: true)
        let fm = FileManager.default
        let appEntries = (try? fm.contentsOfDirectory(atPath: appXPCServicesURL.path)) ?? []
        let frameworkEntries = (try? fm.contentsOfDirectory(atPath: frameworkXPCServicesURL.path)) ?? []

        let combinedEntries = appEntries + frameworkEntries
        let installerEntries = combinedEntries.filter { $0.localizedCaseInsensitiveContains("Installer") }
        if installerEntries.isEmpty {
            VoxtLog.warning(
                """
                Sparkle installer check: installer services not found.
                appXPCServices=\(appXPCServicesURL.path) entries=\(appEntries)
                frameworkXPCServices=\(frameworkXPCServicesURL.path) entries=\(frameworkEntries)
                """
            )
            return
        }

        VoxtLog.info("Sparkle installer check: found installer services \(installerEntries)")
    }
}

private extension AppUpdateManager.CheckSource {
    var description: String {
        switch self {
        case .automatic:
            return "automatic"
        case .manual:
            return "manual"
        }
    }
}

extension Notification.Name {
    static let voxtUpdateAvailabilityDidChange = Notification.Name("voxt.update.availability.didChange")
}
