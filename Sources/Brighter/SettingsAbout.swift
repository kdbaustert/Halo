import AppKit
import SwiftUI

/// The About tab: which build this is, its updates, and where the source lives.
struct AboutSettings: View {
    @ObservedObject private var updater = Updater.shared

    private static let repositoryURL = URL(string: "https://github.com/kdbaustert/Halo")!

    var body: some View {
        SettingsPage(title: "About") {
            hero

            SettingsSection(
                title: "Updates",
                footer: Updater.isConfigured
                    ? "Updates come over HTTPS and are checked against Halo's signing key before "
                        + "anything installs, so a swapped download can't install a different app."
                    : "This build has no update feed. It came from build.sh, not a release, and a "
                        + "local build shouldn't replace itself with the published one."
            ) {
                SettingsRow(
                    title: "Check for updates",
                    subtitle: Self.lastCheckDescription(updater.lastCheck)
                ) {
                    Button("Check Now") { updater.checkForUpdates() }
                        .disabled(!updater.canCheck || !Updater.isConfigured)
                }
                SettingsToggle(
                    title: "Check automatically",
                    subtitle: "Look for a new version about once a day.",
                    isOn: Binding(
                        get: { updater.automaticallyChecks },
                        set: { updater.automaticallyChecks = $0 }))
                    .disabled(!Updater.isConfigured)
                SettingsToggle(
                    title: "Install automatically",
                    subtitle: "Download and install without asking. Halo relaunches to finish, "
                        + "which drops the boost for a moment.",
                    isOn: Binding(
                        get: { updater.automaticallyDownloads },
                        set: { updater.automaticallyDownloads = $0 }))
                    .disabled(!Updater.isConfigured || !updater.automaticallyChecks)
                SettingsToggle(
                    title: "Receive beta updates",
                    subtitle: "Get new versions before they're released to everyone.",
                    isOn: Binding(
                        get: { updater.receivesBetas },
                        set: { updater.receivesBetas = $0 }))
                    .disabled(!Updater.isConfigured)
            }

            SettingsSection(title: "Build") {
                SettingsRow(title: "Version") {
                    Text(Self.version)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
                SettingsRow(title: "Source", subtitle: "Open the repository in your browser.") {
                    Button("View on GitHub") { NSWorkspace.shared.open(Self.repositoryURL) }
                }
            }

            Text(Self.copyright)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .center)
        }
    }

    private var hero: some View {
        let card = RoundedRectangle(cornerRadius: SettingsChrome.cardCorner, style: .continuous)
        return HStack(spacing: 16) {
            Group {
                if let icon = NSImage(named: "AppIcon") {
                    Image(nsImage: icon).resizable().interpolation(.high)
                } else {
                    Image(systemName: "sun.max.fill").resizable()
                }
            }
            .scaledToFit()
            .frame(width: 72, height: 72)

            VStack(alignment: .leading, spacing: 4) {
                Text("Halo").font(.system(size: 20, weight: .semibold))
                Text("Version \(Self.version)")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                Text("Pushes an XDR or HDR display past its normal maximum brightness.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(card.fill(SettingsChrome.cardFill))
        .overlay(card.strokeBorder(SettingsChrome.cardBorder, lineWidth: SettingsChrome.hairline))
    }

    /// "Never checked." stays visible on purpose: an updater that has never run is the problem
    /// this row is there to show.
    private static func lastCheckDescription(_ date: Date?) -> String {
        guard let date else { return "Never checked." }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return "Last checked \(formatter.localizedString(for: date, relativeTo: Date()))."
    }

    /// `1.2.3 (45)`, or just the short version when the build number matches it.
    private static var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String
        guard let build, build != short else { return short }
        return "\(short) (\(build))"
    }

    private static var copyright: String {
        Bundle.main.infoDictionary?["NSHumanReadableCopyright"] as? String ?? ""
    }
}
