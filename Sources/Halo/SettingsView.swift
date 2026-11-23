import SwiftUI

enum SettingsTab: String, CaseIterable, Identifiable {
    case general
    case apps
    case shortcuts
    case about

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: return "General"
        case .apps: return "Apps"
        case .shortcuts: return "Shortcuts"
        case .about: return "About"
        }
    }

    var symbol: String {
        switch self {
        case .general: return "gearshape.2.fill"
        case .apps: return "square.grid.2x2.fill"
        case .shortcuts: return "command.circle.fill"
        case .about: return "info.circle.fill"
        }
    }

    /// The same badge colours Cmd-Tab gives these tabs. Apps has no Cmd-Tab tab, so it's the
    /// system green.
    var gradient: [Color] {
        switch self {
        case .general: return [Color(rgb: 0x8E8E93), Color(rgb: 0x6C6C70)]
        case .apps: return [Color(rgb: 0x34C759), Color(rgb: 0x248A3D)]
        case .shortcuts: return [Color(rgb: 0x6E7BFF), Color(rgb: 0x3B45D6)]
        case .about: return [Color(rgb: 0xB8B8BE), Color(rgb: 0x95959B)]
        }
    }
}

struct SettingsRootView: View {
    @ObservedObject var settings: AppSettings
    @State private var tab = SettingsTab.general

    var body: some View {
        HStack(spacing: 0) {
            sidebar
                .frame(width: 212)
                .background(VisualEffectBackground(material: .sidebar))
            Divider()
            // No background: the window's glass shows through here.
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 600, idealWidth: 640, minHeight: 360, idealHeight: 400)
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(SettingsTab.allCases) { candidate in
                tabRow(candidate)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8)
        // Clears the traffic lights, which sit over the sidebar in a full-height-content window.
        .padding(.top, 44)
        .accessibilityLabel("Settings sections")
    }

    private func tabRow(_ candidate: SettingsTab) -> some View {
        let shape = RoundedRectangle(cornerRadius: 7, style: .continuous)
        return Button {
            tab = candidate
        } label: {
            HStack(spacing: 9) {
                SettingsTabIcon(symbol: candidate.symbol, gradient: candidate.gradient)
                Text(candidate.title).font(.system(size: 13)).lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(shape.fill(tab == candidate ? Color.primary.opacity(0.10) : .clear))
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        // The selected tab is shown only by a tint, which VoiceOver can't see.
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(candidate.title))
        .accessibilityAddTraits(tab == candidate ? [.isButton, .isSelected] : .isButton)
    }

    @ViewBuilder
    private var content: some View {
        switch tab {
        case .general: GeneralSettings(settings: settings)
        case .apps: AppRuleSettings(settings: settings)
        case .shortcuts: ShortcutSettings(settings: settings)
        case .about: AboutSettings()
        }
    }
}

private struct GeneralSettings: View {
    @ObservedObject var settings: AppSettings

    var body: some View {
        SettingsPage(title: "General", subtitle: "How Halo starts and where it shows.") {
            SettingsSection(title: "Menu bar") {
                SettingsToggle(
                    title: "Show icon in menu bar",
                    subtitle: "When it's hidden, open Halo again to get back to Settings.",
                    isOn: $settings.showsMenuBarIcon)
            }
            SettingsSection(title: "Startup") {
                SettingsToggle(
                    title: "Launch at login",
                    subtitle: settings.loginItemMessage,
                    isOn: Binding(
                        get: { settings.launchesAtLogin },
                        set: { settings.setLaunchesAtLogin($0) }))
                SettingsToggle(
                    title: "Turn the boost back on at launch",
                    subtitle: "If it was on when Halo quit.",
                    isOn: $settings.restoresBoost)
            }
            SettingsSection(title: "Brightness") {
                SettingsToggle(
                    title: "Pause the boost when the screen is dimmed",
                    subtitle: Self.pauseSubtitle,
                    isOn: $settings.pausesWhenDimmed)
                SettingsToggle(
                    title: "Switch external displays to HDR while boosting",
                    subtitle: "They can't be boosted without it. The screen blanks as it switches.",
                    isOn: $settings.switchesOnHDR)
            }
        }
        // The item can be switched off in System Settings while this window is closed.
        .onAppear(perform: settings.refreshLoginItem)
    }

    /// Read from `FullBrightnessRule` so the text can't drift from what the rule does.
    private static var pauseSubtitle: String {
        let dimmed = Int((FullBrightnessRule.dimmedLevel * 100).rounded())
        return "Below \(dimmed)%, until it's back at 100%. Turn off if auto-brightness trips it."
    }
}

private struct AppRuleSettings: View {
    @ObservedObject var settings: AppSettings

    var body: some View {
        SettingsPage(title: "Apps", subtitle: "Turn the boost on or off while an app is in front.") {
            SettingsSection(
                title: "Rules",
                footer: "Switching to an app with no rule puts the boost back the way it was. "
                    + "A change you make yourself in between stays."
            ) {
                ForEach(sortedBundleIDs, id: \.self, content: row(for:))
                SettingsRow(title: "Add an app") {
                    Button("Choose…", action: chooseApps)
                }
            }
        }
    }

    private var sortedBundleIDs: [String] {
        settings.appRules.keys.sorted {
            Self.name(of: $0).localizedStandardCompare(Self.name(of: $1)) == .orderedAscending
        }
    }

    private func row(for bundleID: String) -> some View {
        SettingsRow(title: Self.name(of: bundleID)) {
            HStack(spacing: 4) {
                Picker(
                    "",
                    selection: Binding(
                        get: { settings.appRules[bundleID] ?? .noBoost },
                        set: { settings.appRules[bundleID] = $0 })
                ) {
                    ForEach(AppBoostRule.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                .labelsHidden()
                .frame(width: 128)

                Button {
                    settings.appRules[bundleID] = nil
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Remove this app")
            }
        }
    }

    /// A new app starts as Don't boost, the case most worth a rule: HDR video and photo apps
    /// already use the headroom, and boosting on top clips their highlights. Halo itself is
    /// skipped, since the boost never follows it.
    private func chooseApps() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowsMultipleSelection = true
        panel.prompt = "Add"
        guard panel.runModal() == .OK else { return }
        for url in panel.urls {
            guard let bundleID = Bundle(url: url)?.bundleIdentifier,
                bundleID != Bundle.main.bundleIdentifier, settings.appRules[bundleID] == nil
            else { continue }
            settings.appRules[bundleID] = .noBoost
        }
    }

    /// Falls back to the bundle ID for an app that's been deleted since.
    private static func name(of bundleID: String) -> String {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
        else { return bundleID }
        let name = FileManager.default.displayName(atPath: url.path)
        return name.hasSuffix(".app") ? String(name.dropLast(4)) : name
    }
}

private struct ShortcutSettings: View {
    @ObservedObject var settings: AppSettings

    var body: some View {
        SettingsPage(title: "Shortcuts", subtitle: "Work from any app, with no extra permission.") {
            SettingsSection(
                title: "Boost",
                footer: "Hold Command, Option or Control with the key. Escape cancels recording."
            ) {
                ForEach(ShortcutAction.allCases, id: \.self) { action in
                    SettingsRow(
                        title: action.title,
                        subtitle: settings.shortcutErrors[action] ?? Self.subtitle(for: action)
                    ) {
                        ShortcutRecorder(settings: settings, action: action)
                    }
                }
            }
        }
        // Switching tabs takes the recorder off screen with nothing left to show it's recording.
        .onDisappear(perform: settings.stopRecordingShortcut)
    }

    /// The step is read from `BoostFactor` so the text can't drift from what a press does.
    private static func subtitle(for action: ShortcutAction) -> String {
        let step = Int((BoostFactor.step * 100).rounded())
        switch action {
        case .toggleBoost: return "Turns the boost on or off."
        case .increaseBoost: return "Raises the boost \(step)%, or turns it on."
        case .decreaseBoost: return "Lowers the boost \(step)%."
        }
    }
}

private struct ShortcutRecorder: View {
    @ObservedObject var settings: AppSettings
    let action: ShortcutAction

    var body: some View {
        HStack(spacing: 4) {
            Button(label) {
                if isRecording {
                    settings.stopRecordingShortcut()
                } else {
                    settings.startRecordingShortcut(for: action)
                }
            }
            .frame(width: 128)
            .foregroundStyle(settings.shortcutErrors[action] == nil ? Color.primary : Color.orange)

            Button {
                settings.setShortcut(nil, for: action)
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Clear this shortcut")
            // Hidden rather than removed, so the recorder doesn't shift when it appears.
            .opacity(shortcut == nil ? 0 : 1)
            .disabled(shortcut == nil)
        }
    }

    private var shortcut: KeyCombo? { settings.shortcuts[action] }
    /// Only this row's recording. Another row recording still shows this one's shortcut.
    private var isRecording: Bool { settings.recordingAction == action }

    private var label: String {
        if isRecording { return "Press keys…" }
        return shortcut?.displayString ?? "Not set"
    }
}

extension Color {
    fileprivate init(rgb: UInt32) {
        self.init(
            red: Double((rgb >> 16) & 0xFF) / 255,
            green: Double((rgb >> 8) & 0xFF) / 255,
            blue: Double(rgb & 0xFF) / 255)
    }
}
