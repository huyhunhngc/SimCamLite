import AppKit
import Combine
import Sparkle
import UserNotifications

/// Owns Sparkle and mirrors its state for the menus and toolbar.
/// Scheduled checks never interrupt with a window: they post a notification (gentle reminder) instead,
/// since installing quits the app and drops any running stream.
@MainActor
final class UpdateCoordinator: NSObject, ObservableObject, SPUUpdaterDelegate, @preconcurrency SPUStandardUserDriverDelegate,
    UNUserNotificationCenterDelegate {
    nonisolated private static let notificationIdentifier = "SimCamLiteUpdateAvailable"

    @Published private(set) var canCheckForUpdates = false
    @Published private(set) var updateAvailable = false
    @Published private(set) var latestVersion = ""
    @Published private(set) var automaticallyChecksForUpdates = false

    private var controller: SPUStandardUpdaterController!
    private var notificationCenter: UNUserNotificationCenter { .current() }
    private(set) var isEnabled = false

    override init() {
        super.init()
        controller = SPUStandardUpdaterController(startingUpdater: false, updaterDelegate: self, userDriverDelegate: self)
        notificationCenter.delegate = self
        controller.updater.publisher(for: \.canCheckForUpdates)
            .receive(on: DispatchQueue.main)
            .assign(to: &$canCheckForUpdates)
        controller.updater.publisher(for: \.automaticallyChecksForUpdates)
            .receive(on: DispatchQueue.main)
            .assign(to: &$automaticallyChecksForUpdates)
    }

    /// Builds without Config/Environment.xcconfig have an empty feed URL; the updater stays off there.
    func start() {
        guard !isEnabled,
              let feed = Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") as? String, !feed.isEmpty,
              ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil else { return }
        isEnabled = true
        controller.startUpdater()
    }

    func checkForUpdates() {
        guard isEnabled else { return }
        NSApp.activate(ignoringOtherApps: true)
        controller.checkForUpdates(nil)
    }

    var lastUpdateCheckDate: Date? {
        controller.updater.lastUpdateCheckDate
    }

    func setAutomaticallyChecksForUpdates(_ enabled: Bool) {
        controller.updater.automaticallyChecksForUpdates = enabled
    }

    // MARK: SPUUpdaterDelegate

    func updater(_ updater: SPUUpdater, willScheduleUpdateCheckAfterDelay delay: TimeInterval) {
        notificationCenter.requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        updateAvailable = true
        latestVersion = item.displayVersionString
    }

    func updaterDidNotFindUpdate(_ updater: SPUUpdater) {
        updateAvailable = false
        latestVersion = ""
    }

    // MARK: SPUStandardUserDriverDelegate

    var supportsGentleScheduledUpdateReminders: Bool { true }

    func standardUserDriverWillHandleShowingUpdate(_ handleShowingUpdate: Bool, forUpdate update: SUAppcastItem,
                                                   state: SPUUserUpdateState) {
        updateAvailable = true
        latestVersion = update.displayVersionString
        guard !state.userInitiated else { return }

        let content = UNMutableNotificationContent()
        content.title = "SimCam Lite \(update.displayVersionString) is available"
        content.body = "Click to see what's new and install the update."
        content.sound = .default
        notificationCenter.add(UNNotificationRequest(identifier: Self.notificationIdentifier, content: content, trigger: nil))
    }

    func standardUserDriverDidReceiveUserAttention(forUpdate update: SUAppcastItem) {
        notificationCenter.removeDeliveredNotifications(withIdentifiers: [Self.notificationIdentifier])
    }

    // MARK: UNUserNotificationCenterDelegate

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                            withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                            withCompletionHandler completionHandler: @escaping () -> Void) {
        guard response.notification.request.identifier == Self.notificationIdentifier,
              response.actionIdentifier == UNNotificationDefaultActionIdentifier else {
            completionHandler()
            return
        }
        Task { @MainActor [weak self] in
            self?.checkForUpdates()
            completionHandler()
        }
    }
}
