import AppKit
import Sparkle

/// Auto-update through Sparkle, which checks the release feed, verifies the download's EdDSA
/// signature against `SUPublicEDKey` and swaps the bundle.
///
/// Wraps the controller because two of the updater's facts are wanted as SwiftUI state, whether a
/// check can start right now and when the last one finished, and both are only reachable by KVO.
@MainActor
final class Updater: ObservableObject {
    static let shared = Updater()

    /// Nil in a build with no feed, so nothing schedules checks there. Every accessor below is
    /// then a no-op.
    private let controller: SPUStandardUpdaterController?

    /// False while a check is running, so the button can't start a second one.
    @Published private(set) var canCheck = true
    /// Nil until the first check finishes.
    @Published private(set) var lastCheck: Date?

    /// Sparkle's own preference, written straight through. Sparkle reads its key when it schedules,
    /// so a copy kept here would be one the timer ignores.
    var automaticallyChecks: Bool {
        get { controller?.updater.automaticallyChecksForUpdates ?? false }
        set {
            objectWillChange.send()
            controller?.updater.automaticallyChecksForUpdates = newValue
        }
    }

    /// Off by default (see Info.plist): an update relaunches Halo, which drops the boost for a
    /// moment, so it asks first.
    var automaticallyDownloads: Bool {
        get { controller?.updater.automaticallyDownloadsUpdates ?? false }
        set {
            objectWillChange.send()
            controller?.updater.automaticallyDownloadsUpdates = newValue
        }
    }

    private var observers: [NSKeyValueObservation] = []

    private init() {
        guard Self.isConfigured else {
            controller = nil
            canCheck = false
            return
        }
        let controller = SPUStandardUpdaterController(
            startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
        self.controller = controller
        canCheck = controller.updater.canCheckForUpdates
        lastCheck = controller.updater.lastUpdateCheckDate
        observers = [
            controller.updater.observe(\.canCheckForUpdates, options: [.new]) {
                [weak self] updater, _ in
                MainActor.assumeIsolated { self?.canCheck = updater.canCheckForUpdates }
            },
            controller.updater.observe(\.lastUpdateCheckDate, options: [.new]) {
                [weak self] updater, _ in
                MainActor.assumeIsolated { self?.lastCheck = updater.lastUpdateCheckDate }
            },
        ]
    }

    /// The button in Settings. Unlike the scheduled check, this one says so when there's nothing
    /// new.
    func checkForUpdates() {
        controller?.updater.checkForUpdates()
    }

    /// False for a `build.sh` bundle: the script strips `SUFeedURL` from anything that isn't a
    /// release, so a local build never replaces itself with the published one. Static so the app
    /// can ask before building the updater it gates.
    static var isConfigured: Bool {
        let info = Bundle.main.infoDictionary
        let feed = info?["SUFeedURL"] as? String ?? ""
        let key = info?["SUPublicEDKey"] as? String ?? ""
        return !feed.isEmpty && !key.isEmpty
    }
}
