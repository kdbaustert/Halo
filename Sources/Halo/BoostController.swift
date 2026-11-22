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
            if !isEnabled { isBuiltInPaused = false }
            lastBrightness = SystemBrightness.builtInLevel()
            saveWantsBoost()
            if isEnabled {
                start()
                // After the start: the mode change can deliver its screen-parameter notification
                // before it returns, and a rebuild in the middle of starting would leave two sets
                // of boosters.
                switchOnHDR()
            } else {
                stop()
                restoreHDR()
            }
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

    /// The dimmed built-in display is left out of a boost that carries on for the external ones,
    /// until its brightness is at 100% again. Switching the boost off ends it.
    @Published private(set) var isBuiltInPaused = false

    /// Whether `FullBrightnessRule` runs at all. Set from Settings. Switching it off while waiting
    /// turns the boost straight back on.
    var pausesWhenDimmed = true {
        didSet {
            guard !pausesWhenDimmed else { return }
            if isWaitingForFullBrightness {
                isEnabled = true
            } else if isBuiltInPaused {
                resumeBuiltIn()
            }
        }
    }

    /// Set from Settings. While the boost is on, external displays that have an HDR mode are put
    /// in it, since they can't be boosted otherwise, and put back when the boost goes off.
    var switchesOnHDR = false {
        didSet {
            guard switchesOnHDR != oldValue else { return }
            if !switchesOnHDR {
                restoreHDR()
            } else if isEnabled {
                switchOnHDR()
            }
            updateCapableDisplays()
        }
    }

    /// Saved on every change, so Settings can turn the boost back on at the next launch. A boost
    /// waiting for full brightness counts as on.
    var wasEnabledAtQuit: Bool { UserDefaults.standard.bool(forKey: Self.wasEnabledKey) }

    /// The built-in display and the external ones each have their own switch and strength. All
    /// external displays share one. These hold which of them `isEnabled` covers, so they keep
    /// their values while the boost is off and the toggle shortcut brings the same ones back.
    @Published private(set) var boostsBuiltIn: Bool {
        didSet {
            guard boostsBuiltIn != oldValue else { return }
            UserDefaults.standard.set(boostsBuiltIn, forKey: Self.boostsBuiltInKey)
            // Nothing is left to wait for: the brightness rule only ever watched this display.
            if !boostsBuiltIn {
                isWaitingForFullBrightness = false
                isBuiltInPaused = false
            }
            boostedDisplaysChanged()
        }
    }

    @Published private(set) var boostsExternal: Bool {
        didSet {
            guard boostsExternal != oldValue else { return }
            UserDefaults.standard.set(boostsExternal, forKey: Self.boostsExternalKey)
            boostedDisplaysChanged()
        }
    }

    /// What the menu's switches show and set. The first one switched on starts the boost and
    /// the last one switched off stops it.
    var isBoostingBuiltIn: Bool {
        get { isEnabled && boostsBuiltIn }
        set { setBoosting(builtIn: newValue, external: isBoostingExternal) }
    }

    var isBoostingExternal: Bool {
        get { isEnabled && boostsExternal }
        set { setBoosting(builtIn: isBoostingBuiltIn, external: newValue) }
    }

    @Published var builtInFactor: Double {
        didSet {
            UserDefaults.standard.set(builtInFactor, forKey: BoostFactor.defaultsKey)
            applyAll()
        }
    }

    @Published var externalFactor: Double {
        didSet {
            UserDefaults.standard.set(externalFactor, forKey: BoostFactor.externalDefaultsKey)
            applyAll()
        }
    }

    @Published private(set) var errorMessage: String?
    @Published private(set) var hasCapableBuiltIn = false
    /// Counts a display that would be capable once switched to HDR mode, or the boost couldn't
    /// be turned on with only that display connected.
    @Published private(set) var hasCapableExternal = false
    var hasCapableDisplay: Bool { hasCapableBuiltIn || hasCapableExternal }

    /// ColorSync, display wake and other apps put the system's table back without telling anyone,
    /// so the boosted table is rewritten on this interval. The screen sits unboosted until the
    /// next write, so it's kept short. Writing the same table doesn't flicker.
    private static let reapplyInterval: TimeInterval = 0.5
    /// Only while waiting. With the boost on, brightness changes post screen-parameter
    /// notifications, and the reapply timer catches any that don't.
    private static let brightnessPollInterval: TimeInterval = 1
    /// macOS keeps a brightness level for each display arrangement and ramps to it when a display
    /// is plugged in or pulled. That took the built-in to 79% about a second after the unplug.
    private static let brightnessSettleInterval: TimeInterval = 5
    private static let wasEnabledKey = "boostWasEnabled"
    private static let boostsBuiltInKey = "boostsBuiltIn"
    private static let boostsExternalKey = "boostsExternal"

    /// What the boosters were built for. A rebuild is only needed when this changes.
    private struct DisplayLayout: Equatable {
        let displayID: CGDirectDisplayID
        let frame: NSRect
        /// A new profile means a new table, and the one each booster saved is the old one's.
        let colorSpace: NSColorSpace?
    }

    private let logger = Logger(subsystem: "dev.kennyb.Halo", category: "boost")
    private var boosters: [DisplayBooster] = []
    private var boostedLayout: [DisplayLayout] = []
    private var reapplyTimer: Timer?
    private var brightnessTimer: Timer?
    /// The level at the last check, so only a drop past the dimmed level turns the boost off.
    private var lastBrightness: Float?
    private var connectedDisplays: Set<CGDirectDisplayID> = []
    /// Until then a drop in brightness is macOS's doing, not the user dimming the screen.
    private var brightnessSettlesAt: Date?
    private var observers: [(NotificationCenter, NSObjectProtocol)] = []
    /// Only the ones this turned on, so a display the user keeps in HDR mode stays in it.
    private var displaysSwitchedToHDR: Set<CGDirectDisplayID> = []

    init() {
        let defaults = UserDefaults.standard
        boostsBuiltIn = defaults.object(forKey: Self.boostsBuiltInKey) as? Bool ?? true
        boostsExternal = defaults.object(forKey: Self.boostsExternalKey) as? Bool ?? true
        let savedFactor = defaults.object(forKey: BoostFactor.defaultsKey)
        builtInFactor = BoostFactor.clamped(savedFactor)
        // Until it's been set, the one strength both kinds of display used to share.
        externalFactor = BoostFactor.clamped(
            defaults.object(forKey: BoostFactor.externalDefaultsKey) ?? savedFactor)
        updateCapableDisplays()
        connectedDisplays = Self.connectedDisplayIDs()
        lastBrightness = SystemBrightness.builtInLevel()
        observeSystemEvents()
    }

    /// Turns the boost back on at launch, or waits for full brightness if the screen is dimmed.
    func restore() {
        if pausesWhenDimmed, boostsBuiltIn, let level = SystemBrightness.builtInLevel(),
            FullBrightnessRule.isDimmed(level)
        {
            suspendForDimming()
        } else {
            isEnabled = true
        }
    }

    private func setBoosting(builtIn: Bool, external: Bool) {
        guard builtIn || external else {
            isEnabled = false
            return
        }
        boostsBuiltIn = builtIn
        boostsExternal = external
        isEnabled = true
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
        let timer = Timer(timeInterval: Self.reapplyInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.followBrightness()
                self?.applyAll()
            }
        }
        // Common modes: a default-mode timer stops for as long as a menu is open or a window is
        // being dragged, and the screen would sit unboosted if the table were reset meanwhile.
        RunLoop.main.add(timer, forMode: .common)
        reapplyTimer = timer
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
        let connected = Self.connectedDisplayIDs()
        if connected != connectedDisplays {
            connectedDisplays = connected
            brightnessSettlesAt = Date() + Self.brightnessSettleInterval
        }
        followBrightness()
        // A display plugged in while the boost is on. The mode change posts this notification
        // again, and that pass finds it capable.
        if isEnabled { switchOnHDR() }
        updateCapableDisplays()
        settleDimmingPause()
        guard isEnabled else { return }
        let layout = Self.layout(of: screensToBoost())
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
        guard pausesWhenDimmed, boostsBuiltIn else { return }
        // The level it settles at becomes the one later changes are compared with, so the boost
        // stays on there the same as one switched on by hand while dimmed.
        if let brightnessSettlesAt, Date() < brightnessSettlesAt { return }
        let change = FullBrightnessRule.change(
            from: previous, to: level, isEnabled: isEnabled && !isBuiltInPaused,
            isWaiting: isWaitingForFullBrightness || isBuiltInPaused)
        switch change {
        case .suspend:
            logger.info(
                "Brightness down to \(level, format: .fixed(precision: 3)); boost off until full")
            suspendForDimming()
        case .resume:
            logger.info("Brightness back at full; boost on")
            if isBuiltInPaused { resumeBuiltIn() } else { isEnabled = true }
        case nil:
            break
        }
    }

    /// The built-in's brightness says nothing about an external display, so with one connected
    /// only the built-in's boost stops. Otherwise the whole boost goes off and waits.
    private func suspendForDimming() {
        guard boostsAnExternalDisplay else {
            isEnabled = false
            isWaitingForFullBrightness = true
            return
        }
        isBuiltInPaused = true
        if isEnabled { restart() } else { isEnabled = true }
    }

    /// An external display came or went, or had its boost switched, while the built-in is dimmed,
    /// so the pause changes between the built-in alone and the whole boost.
    private func settleDimmingPause() {
        let carriesOn = boostsAnExternalDisplay
        if (isBuiltInPaused && !carriesOn) || (isWaitingForFullBrightness && carriesOn) {
            suspendForDimming()
        }
    }

    private func boostedDisplaysChanged() {
        settleDimmingPause()
        guard isEnabled else { return }
        // Before the mode change, for the same reason as in `isEnabled`.
        restart()
        if boostsExternal { switchOnHDR() } else { restoreHDR() }
    }

    private func resumeBuiltIn() {
        isBuiltInPaused = false
        restart()
    }

    /// Stopped first so the new boosters save the normal tables, not the boosted ones.
    private func restart() {
        stop()
        start()
    }

    private func switchOnHDR() {
        guard switchesOnHDR, boostsExternal else { return }
        for displayID in Self.displaysAwaitingHDR() {
            if HDRMode.setEnabled(true, for: displayID) {
                displaysSwitchedToHDR.insert(displayID)
            } else {
                logger.error("Couldn't switch display \(displayID) to HDR mode")
            }
        }
    }

    /// Skips a display that's been unplugged since; its ID may belong to nothing now.
    private func restoreHDR() {
        for displayID in displaysSwitchedToHDR.intersection(Self.connectedDisplayIDs())
        where !HDRMode.setEnabled(false, for: displayID) {
            logger.error("Couldn't switch display \(displayID) back out of HDR mode")
        }
        displaysSwitchedToHDR = []
    }

    /// Runs on every screen-parameter notification, and setting a value publishes even when it
    /// hasn't changed, which redraws the menu.
    private func updateCapableDisplays() {
        let capable = Self.capableScreens().map(\.1)
        let builtIn = capable.contains(where: Self.isBuiltIn)
        let external =
            !capable.allSatisfy(Self.isBuiltIn)
            || (switchesOnHDR && !Self.displaysAwaitingHDR().isEmpty)
        if hasCapableBuiltIn != builtIn { hasCapableBuiltIn = builtIn }
        if hasCapableExternal != external { hasCapableExternal = external }
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
        let screens = screensToBoost()
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
            let factor = Self.isBuiltIn(booster.displayID) ? builtInFactor : externalFactor
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
        observe(app, NSApplication.willTerminateNotification) { $0.shutDown() }
    }

    /// The observers go first: leaving HDR mode posts a screen-parameter change, and a rebuild
    /// with the boost still on would switch it straight back.
    private func shutDown() {
        observers.forEach { $0.0.removeObserver($0.1) }
        observers = []
        stop()
        restoreHDR()
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

    private func screensToBoost() -> [(NSScreen, CGDirectDisplayID)] {
        Self.capableScreens().filter { _, displayID in
            Self.isBuiltIn(displayID) ? boostsBuiltIn && !isBuiltInPaused : boostsExternal
        }
    }

    private var boostsAnExternalDisplay: Bool {
        boostsExternal && Self.capableScreens().contains { !Self.isBuiltIn($0.1) }
    }

    private static func isBuiltIn(_ displayID: CGDirectDisplayID) -> Bool {
        CGDisplayIsBuiltin(displayID) != 0
    }

    /// Screens that can show light past SDR white. Displays without EDR report 1.0.
    private static func capableScreens() -> [(NSScreen, CGDirectDisplayID)] {
        NSScreen.screens.compactMap { screen in
            guard screen.maximumPotentialExtendedDynamicRangeColorComponentValue > 1,
                let displayID = displayID(of: screen)
            else { return nil }
            return (screen, displayID)
        }
    }

    private static func displaysAwaitingHDR() -> [CGDirectDisplayID] {
        NSScreen.screens.compactMap(displayID(of:)).filter(HDRMode.canSwitchOn)
    }

    private static func connectedDisplayIDs() -> Set<CGDirectDisplayID> {
        Set(NSScreen.screens.compactMap(displayID(of:)))
    }

    private static func displayID(of screen: NSScreen) -> CGDirectDisplayID? {
        let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")]
        return (number as? NSNumber)?.uint32Value
    }
}
