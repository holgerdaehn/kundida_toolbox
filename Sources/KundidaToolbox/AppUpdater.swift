import AppKit
import Combine
import Sparkle

/// Selbstaktualisierung über Sparkle – wie Forseti.
/// Feed und Schlüssel kommen aus der Info.plist (`SUFeedURL`, `SUPublicEDKey`).
@MainActor
final class AppUpdater: NSObject, ObservableObject, SPUUpdaterDelegate, SPUStandardUserDriverDelegate {
    @Published private(set) var canCheckForUpdates = false
    /// Gefundene neue Toolbox-Version (für den Hinweis im Menüleisten-Fenster).
    @Published private(set) var availableVersion: String?
    private var controller: SPUStandardUpdaterController!

    override init() {
        super.init()
        // Nur aus einem echten .app-Bundle starten (nicht bei `swift run`).
        controller = SPUStandardUpdaterController(
            startingUpdater: Bundle.main.bundleURL.pathExtension == "app",
            updaterDelegate: self,
            userDriverDelegate: self
        )
        controller.updater.publisher(for: \.canCheckForUpdates)
            .receive(on: RunLoop.main)
            .assign(to: &$canCheckForUpdates)
    }

    var automaticallyChecks: Bool {
        get { controller.updater.automaticallyChecksForUpdates }
        set { controller.updater.automaticallyChecksForUpdates = newValue }
    }

    func checkForUpdates() {
        NSApp.activate(ignoringOtherApps: true)
        controller.checkForUpdates(nil)
    }

    // MARK: SPUUpdaterDelegate

    nonisolated func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        let version = item.displayVersionString
        Task { @MainActor in self.availableVersion = version }
    }

    nonisolated func updaterDidNotFindUpdate(_ updater: SPUUpdater) {
        Task { @MainActor in self.availableVersion = nil }
    }

    // MARK: SPUStandardUserDriverDelegate

    /// Menüleisten-App: Sparkle zeigt geplante Updates dezent; wir holen das Fenster nach vorn.
    nonisolated var supportsGentleScheduledUpdateReminders: Bool { true }

    nonisolated func standardUserDriverWillHandleShowingUpdate(_ handleShowingUpdate: Bool, forUpdate update: SUAppcastItem, state: SPUUserUpdateState) {
        Task { @MainActor in NSApp.activate(ignoringOtherApps: true) }
    }
}
