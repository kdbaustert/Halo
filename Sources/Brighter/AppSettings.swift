import AppKit
import Carbon.HIToolbox
import ServiceManagement
import os

/// The things a global shortcut can do. Each one gets its own recorder row in Settings and its
/// own Carbon hot key.
enum ShortcutAction: CaseIterable {
    case toggleBoost
    case increaseBoost
    case decreaseBoost

    /// The row label in Settings, also used to name the action that already owns a combo.
    var title: String {
        switch self {
        case .toggleBoost: return "Toggle boost"
        case .increaseBoost: return "Brighter"
        case .decreaseBoost: return "Dimmer"
        }
    }

    /// The toggle keeps the key it had when it was the only shortcut, so it survives the update.
    fileprivate var defaultsKey: String {
        switch self {
        case .toggleBoost: return "toggleShortcut"
        case .increaseBoost: return "increaseShortcut"
        case .decreaseBoost: return "decreaseShortcut"
        }
    }

    /// Has to differ per action: every hot key handler sees every press and goes by this ID.
    /// Toggle is 1 because that's what the single shortcut used before.
    fileprivate var hotKeyID: UInt32 {
        switch self {
        case .toggleBoost: return 1
        case .increaseBoost: return 2
        case .decreaseBoost: return 3
        }
    }
}

/// What the Settings window changes: the login item, restoring the boost at launch, pausing it
/// on a dimmed screen, and the global shortcuts that toggle and adjust it.
@MainActor
final class AppSettings: ObservableObject {
    @Published var restoresBoost: Bool {
        didSet { UserDefaults.standard.set(restoresBoost, forKey: Self.restoresBoostKey) }
    }

    @Published var pausesWhenDimmed: Bool {
        didSet {
            UserDefaults.standard.set(pausesWhenDimmed, forKey: Self.pausesWhenDimmedKey)
            controller.pausesWhenDimmed = pausesWhenDimmed
        }
    }

    @Published var showsMenuBarIcon: Bool {
        didSet { UserDefaults.standard.set(showsMenuBarIcon, forKey: Self.showsMenuBarIconKey) }
    }

    /// Mirrors the system's Login Items list rather than our own defaults, so a change made in
    /// System Settings shows up here.
    @Published private(set) var launchesAtLogin: Bool
    @Published private(set) var loginItemMessage: String?
    /// No entry means the action has no shortcut. Changed through `setShortcut(_:for:)` so the
    /// save and the hot key stay in step with it.
    @Published private(set) var shortcuts: [ShortcutAction: KeyCombo] = [:]
    /// Shown in place of the row's subtitle. Cleared when the action's shortcut registers.
    @Published private(set) var shortcutErrors: [ShortcutAction: String] = [:]
    /// The action whose shortcut the next key press becomes, if one is recording.
    @Published private(set) var recordingAction: ShortcutAction?

    private static let restoresBoostKey = "restoresBoost"
    private static let pausesWhenDimmedKey = "pausesWhenDimmed"
    private static let showsMenuBarIconKey = "showsMenuBarIcon"

    private let logger = Logger(subsystem: "dev.kennyb.Brighter", category: "settings")
    private let controller: BoostController
    /// Filled once in init and kept for the app's life, since each one installs a Carbon handler
    /// that's never removed.
    private var hotKeys: [ShortcutAction: GlobalHotKey] = [:]
    /// Held here rather than in the recorder view: the view isn't told when the Settings window
    /// closes, and a monitor left behind would swallow every key typed into the app.
    private var recordingMonitor: Any?

    init(controller: BoostController) {
        self.controller = controller
        let defaults = UserDefaults.standard
        restoresBoost = defaults.bool(forKey: Self.restoresBoostKey)
        // On until it's switched off, the way the boost behaved before this was a setting.
        let pauses = defaults.object(forKey: Self.pausesWhenDimmedKey) as? Bool ?? true
        pausesWhenDimmed = pauses
        controller.pausesWhenDimmed = pauses
        // Shown until it's switched off, so a first launch always has the icon.
        showsMenuBarIcon = defaults.object(forKey: Self.showsMenuBarIconKey) as? Bool ?? true
        launchesAtLogin = Self.isOn(SMAppService.mainApp.status)
        for action in ShortcutAction.allCases {
            shortcuts[action] = defaults.data(forKey: action.defaultsKey).flatMap {
                try? JSONDecoder().decode(KeyCombo.self, from: $0)
            }
            hotKeys[action] = GlobalHotKey(id: action.hotKeyID) { [weak self] in
                self?.perform(action)
            }
        }
        registerShortcuts()
        if restoresBoost && controller.wasEnabledAtQuit {
            // Waits for the app to finish launching: the EDR window can't go on screen before.
            DispatchQueue.main.async { controller.restore() }
        }
    }

    // MARK: Login item

    /// Re-reads the system's answer. The window calls this on appear, since the item can be
    /// switched off in System Settings behind our back.
    func refreshLoginItem() {
        let status = SMAppService.mainApp.status
        launchesAtLogin = Self.isOn(status)
        loginItemMessage =
            status == .requiresApproval
            ? "Waiting to be allowed in System Settings > General > Login Items." : nil
    }

    /// The switch shows the status macOS reports afterwards, so a refused change snaps back with
    /// the reason underneath.
    func setLaunchesAtLogin(_ enabled: Bool) {
        let isOn = Self.isOn(SMAppService.mainApp.status)
        do {
            if enabled && !isOn {
                try SMAppService.mainApp.register()
            } else if !enabled && isOn {
                try SMAppService.mainApp.unregister()
            }
            refreshLoginItem()
        } catch {
            let reason = error.localizedDescription
            logger.error("Login item change failed: \(reason, privacy: .public)")
            refreshLoginItem()
            loginItemMessage = "macOS wouldn't change this: \(error.localizedDescription)"
        }
    }

    /// `.requiresApproval` means the registration worked and macOS is waiting on the user, so the
    /// switch stays on rather than reading as a failure.
    private static func isOn(_ status: SMAppService.Status) -> Bool {
        status == .enabled || status == .requiresApproval
    }

    // MARK: Shortcuts

    /// Saves the combo and registers it straight away. Nil clears the shortcut.
    func setShortcut(_ combo: KeyCombo?, for action: ShortcutAction) {
        shortcuts[action] = combo
        saveShortcut(for: action)
        registerShortcut(for: action)
    }

    /// Takes the next key press as the action's shortcut. Escape cancels. Starting on another
    /// row ends any recording already going.
    func startRecordingShortcut(for action: ShortcutAction) {
        stopRecordingShortcut()
        // Otherwise pressing an existing shortcut runs it instead of being recorded.
        hotKeys.values.forEach { $0.unregister() }
        recordingAction = action
        recordingMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) {
            [weak self] event in
            MainActor.assumeIsolated { self?.record(event) }
            return nil
        }
    }

    /// Ends a recording without changing anything and puts every shortcut back. Does nothing
    /// if none is going.
    func stopRecordingShortcut() {
        guard let recordingMonitor else { return }
        NSEvent.removeMonitor(recordingMonitor)
        self.recordingMonitor = nil
        recordingAction = nil
        registerShortcuts()
    }

    /// A combo another action already has is refused with an error on this row, rather than
    /// quietly taken from the other one.
    private func record(_ event: NSEvent) {
        guard let action = recordingAction else { return }
        if event.keyCode == UInt16(kVK_Escape) {
            stopRecordingShortcut()
        } else if let combo = KeyCombo(event: event) {
            stopRecordingShortcut()
            if let owner = actionUsing(combo), owner != action {
                shortcutErrors[action] =
                    "\(combo.displayString) is already set for \(owner.title)."
            } else {
                setShortcut(combo, for: action)
            }
        } else {
            NSSound.beep()
        }
    }

    /// Checked here so the error names the Halo action that has the combo instead of blaming
    /// another app.
    private func actionUsing(_ combo: KeyCombo) -> ShortcutAction? {
        shortcuts.first { $0.value == combo }?.key
    }

    private func registerShortcuts() {
        ShortcutAction.allCases.forEach(registerShortcut(for:))
    }

    /// Replaces the action's hot key with its current shortcut and sets or clears its error.
    private func registerShortcut(for action: ShortcutAction) {
        let combo = shortcuts[action]
        do {
            try hotKeys[action]?.register(combo)
            shortcutErrors[action] = nil
        } catch {
            switch error {
            case .taken:
                shortcutErrors[action] =
                    "Another app already uses \(combo?.displayString ?? "it")."
            case .refused(let status):
                logger.error("RegisterEventHotKey failed: \(status)")
                shortcutErrors[action] = "macOS refused this shortcut (error \(status))."
            }
        }
    }

    private func saveShortcut(for action: ShortcutAction) {
        guard let shortcut = shortcuts[action] else {
            UserDefaults.standard.removeObject(forKey: action.defaultsKey)
            return
        }
        do {
            UserDefaults.standard.set(
                try JSONEncoder().encode(shortcut), forKey: action.defaultsKey)
        } catch {
            logger.error("Couldn't save shortcut: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Ignored with no capable display, the same as the menu's disabled switch.
    private func perform(_ action: ShortcutAction) {
        guard controller.hasCapableDisplay else { return }
        switch action {
        case .toggleBoost:
            controller.isEnabled.toggle()
        case .increaseBoost:
            // From off, the first press turns the boost on at the strength it had.
            if controller.isEnabled {
                controller.factor = BoostFactor.stepped(controller.factor, by: 1)
            } else {
                controller.isEnabled = true
            }
        case .decreaseBoost:
            controller.factor = BoostFactor.stepped(controller.factor, by: -1)
        }
    }
}
