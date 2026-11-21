import AppKit
import os

/// Turns the boost on and off for every display that has EDR headroom, and keeps it applied
/// through display changes, sleep and anything else that resets gamma tables.
@MainActor
final class BoostController: ObservableObject {
    @Published var isEnabled = false {
        didSet {
            guard isEnabled != oldValue else { return }
            // Any change ends a wait for full brightness, including the rule's own: it turns the
            // boost off first and starts waiting after.
            isWaitingForFullBrightness = false
            lastBrightness = SystemBrightness.builtInLevel()
            saveWantsBoost()
            if isEnabled { start() } else { stop() }
        }
    }

    /// Turned off by dimming the screen, and turns back on once brightness is at 100% again.
    @Published private(set) var isWaitingForFullBrightness = false {
        didSet {
            guard isWaitingForFullBrightness != oldValue else { return }
            saveWantsBoost()
            if isWaitingForFullBrightness {
                startWatchingBrightness()
            } else {
                stopWatchingBrightness()
            }
        }
    }

    /// Whether `FullBrightnessRule` runs at all. Set from Settings. Switching it off while waiting
    /// turns the boost straight back on.
    var pausesWhenDimmed = true {
        didSet {
            guard !pausesWhenDimmed, isWaitingForFullBrightness else { return }
            isEnabled = true
        }
    }

    /// Saved on every change, so Settings can turn the boost back on at the next launch. A boost
    /// waiting for full brightness counts as on.
    var wasEnabledAtQuit: Bool { UserDefaults.standard.bool(forKey: Self.wasEnabledKey) }

    @Published var factor: Double {
        didSet {
            UserDefaults.standard.set(factor, forKey: BoostFactor.defaultsKey)
            applyAll()
        }
    }

    @Published private(set) var errorMessage: String?
    @Published private(set) var hasCapableDisplay = false

    /// ColorSync, display wake and other apps put the system's table back without telling anyone,
    /// so the boosted table is rewritten on this interval. The screen sits unboosted until the
    /// next write, so it's kept short. Writing the same table doesn't flicker.
    private static let reapplyInterval: TimeInterval = 0.5
    /// Only while waiting. With the boost on, brightness changes post screen-parameter
    /// notifications, and the reapply timer catches any that don't.
    private static let brightnessPollInterval: TimeInterval = 1
    private static let wasEnabledKey = "boostWasEnabled"

    /// What the boosters were built for. A rebuild is only needed when this changes.
    private struct DisplayLayout: Equatable {
        let displayID: CGDirectDisplayID
        let frame: NSRect
        /// A new profile means a new table, and the one each booster saved is the old one's.
        let colorSpace: NSColorSpace?
    }

    private let logger = Logger(subsystem: "dev.kennyb.Brighter", category: "boost")
    private var boosters: [DisplayBooster] = []
    private var boostedLayout: [DisplayLayout] = []
    private var reapplyTimer: Timer?
    private var brightnessTimer: Timer?
    /// The level at the last check, so only a drop past the dimmed level turns the boost off.
    private var lastBrightness: Float?
    private var observers: [(NotificationCenter, NSObjectProtocol)] = []

    init() {
        factor = BoostFactor.clamped(UserDefaults.standard.object(forKey: BoostFactor.defaultsKey))
        hasCapableDisplay = !Self.capableScreens().isEmpty
        lastBrightness = SystemBrightness.builtInLevel()
        observeSystemEvents()
    }

    /// Turns the boost back on at launch, or waits for full brightness if the screen is dimmed.
    func restore() {
        if pausesWhenDimmed, let level = SystemBrightness.builtInLevel(),
            FullBrightnessRule.isDimmed(level)
        {
            isWaitingForFullBrightness = true
        } else {
            isEnabled = true
        }
    }

    private func start() {
        do {
            try createBoosters()
            try applyBoosters()
            errorMessage = nil
        } catch {
            stop()
            report(error)
            isEnabled = false
            return
        }
        reapplyTimer = Timer.scheduledTimer(
            withTimeInterval: Self.reapplyInterval, repeats: true
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.followBrightness()
                self?.applyAll()
            }
        }
    }

    private func stop() {
        reapplyTimer?.invalidate()
        reapplyTimer = nil
        for booster in boosters {
            do {
                try booster.stop()
            } catch {
                report(error)
            }
        }
        boosters = []
        boostedLayout = []
    }

    private func applyAll() {
        guard isEnabled else { return }
        do {
            try applyBoosters()
            // Setting it publishes even when it's already nil, which redraws the menu bar icon.
            if errorMessage != nil { errorMessage = nil }
        } catch {
            report(error)
        }
    }

    /// A new arrangement or resolution can swap display IDs and reload their tables, so the
    /// boosters are rebuilt from scratch rather than reapplied. Brightness changes post the same
    /// notification dozens of times a second as EDR headroom moves; rebuilding on those restored
    /// the normal table each time and made the screen flicker, so they only reapply.
    private func rebuild() {
        followBrightness()
        let screens = Self.capableScreens()
        hasCapableDisplay = !screens.isEmpty
        guard isEnabled else { return }
        let layout = Self.layout(of: screens)
        guard layout != boostedLayout else {
            applyAll()
            return
        }
        let profileChanged = layout.map(\.colorSpace) != boostedLayout.map(\.colorSpace)
        logger.info("Display layout changed; rebuilding boosters")
        stop()
        // Stopping put back the old profile's table, so the boosters would save that again.
        if profileChanged { CGDisplayRestoreColorSyncSettings() }
        start()
    }

    private func followBrightness() {
        guard let level = SystemBrightness.builtInLevel() else { return }
        let previous = lastBrightness ?? level
        // Kept current even with the rule off, so switching it on doesn't compare against a
        // level from before.
        lastBrightness = level
        guard pausesWhenDimmed else { return }
        let change = FullBrightnessRule.change(
            from: previous, to: level, isEnabled: isEnabled, isWaiting: isWaitingForFullBrightness)
        switch change {
        case .suspend:
            logger.info(
                "Brightness down to \(level, format: .fixed(precision: 3)); boost off until full")
            isEnabled = false
            isWaitingForFullBrightness = true
        case .resume:
            logger.info("Brightness back at full; boost on")
            isEnabled = true
        case nil:
            break
        }
    }

    private func startWatchingBrightness() {
        brightnessTimer = Timer.scheduledTimer(
            withTimeInterval: Self.brightnessPollInterval, repeats: true
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.followBrightness() }
        }
    }

    private func stopWatchingBrightness() {
        brightnessTimer?.invalidate()
        brightnessTimer = nil
    }

    private func saveWantsBoost() {
        let wantsBoost = isEnabled || isWaitingForFullBrightness
        UserDefaults.standard.set(wantsBoost, forKey: Self.wasEnabledKey)
    }

    private func createBoosters() throws {
        let screens = Self.capableScreens()
        boosters = try screens.map { screen, displayID in
            try DisplayBooster(screen: screen, displayID: displayID)
        }
        boostedLayout = Self.layout(of: screens)
    }

    private static func layout(of screens: [(NSScreen, CGDirectDisplayID)]) -> [DisplayLayout] {
        screens.map { screen, displayID in
            DisplayLayout(displayID: displayID, frame: screen.frame, colorSpace: screen.colorSpace)
        }
    }

    private func applyBoosters() throws {
        for booster in boosters {
            try booster.apply(factor: Float(factor))
        }
    }

    private func report(_ error: Error) {
        let message = (error as? BoostError)?.message ?? error.localizedDescription
        logger.error("\(message, privacy: .public)")
        errorMessage = message
    }

    private func observeSystemEvents() {
        let app = NotificationCenter.default
        let workspace = NSWorkspace.shared.notificationCenter
        observe(app, NSApplication.didChangeScreenParametersNotification) { $0.rebuild() }
        observe(app, NSScreen.colorSpaceDidChangeNotification) { $0.rebuild() }
        observe(workspace, NSWorkspace.didWakeNotification) { $0.applyAll() }
        observe(workspace, NSWorkspace.screensDidWakeNotification) { $0.applyAll() }
        // CoreGraphics also drops our tables when the process exits, but a clean quit shouldn't
        // depend on that.
        observe(app, NSApplication.willTerminateNotification) { $0.stop() }
    }

    private func observe(
        _ center: NotificationCenter, _ name: Notification.Name,
        perform action: @escaping @MainActor (BoostController) -> Void
    ) {
        let token = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                action(self)
            }
        }
        observers.append((center, token))
    }

    /// Screens that can show light past SDR white. Displays without EDR report 1.0.
    private static func capableScreens() -> [(NSScreen, CGDirectDisplayID)] {
        NSScreen.screens.compactMap { screen in
            guard screen.maximumPotentialExtendedDynamicRangeColorComponentValue > 1,
                let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")]
                    as? NSNumber
            else { return nil }
            return (screen, number.uint32Value)
        }
    }
}
