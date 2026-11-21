import SwiftUI

@main
struct BrighterApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var controller: BoostController
    @StateObject private var settings: AppSettings
    private let settingsPresenter: SettingsPresenter

    init() {
        let controller = BoostController()
        let settings = AppSettings(controller: controller)
        _controller = StateObject(wrappedValue: controller)
        _settings = StateObject(wrappedValue: settings)
        settingsPresenter = SettingsPresenter(settings: settings)
        appDelegate.reopen = settingsPresenter.show
    }

    var body: some Scene {
        MenuBarExtra(isInserted: menuBarIconShown) {
            BoostMenu(controller: controller, openSettings: settingsPresenter.show)
        } label: {
            Image(systemName: controller.isEnabled ? "sun.max.fill" : "sun.max")
        }
        .menuBarExtraStyle(.window)
    }

    /// MenuBarExtra writes this back on every scene update, unchanged, and an unchanged write to
    /// a @Published property still republishes. That redraws the scene, which writes it again,
    /// and the loop froze the app. Only a real change gets through.
    private var menuBarIconShown: Binding<Bool> {
        Binding(
            get: { settings.showsMenuBarIcon },
            set: { shown in
                guard shown != settings.showsMenuBarIcon else { return }
                settings.showsMenuBarIcon = shown
            })
    }
}

/// Opening Halo again from Finder or Spotlight shows Settings. With the menu bar icon hidden,
/// that's the only way back in.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    var reopen: (() -> Void)?

    func applicationShouldHandleReopen(
        _ sender: NSApplication, hasVisibleWindows flag: Bool
    ) -> Bool {
        reopen?()
        return false
    }
}

/// Laid out like the system's own menu bar menus (Wi-Fi, Bluetooth): a header with the switch,
/// then the rest as full-width items.
private struct BoostMenu: View {
    @ObservedObject var controller: BoostController
    let openSettings: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            if controller.hasCapableDisplay {
                strength
            } else {
                note("No XDR or HDR display is connected.", color: .secondary)
            }
            if controller.isWaitingForFullBrightness {
                note("Turns back on when brightness is at 100%.", color: .secondary)
            }
            if let message = controller.errorMessage {
                note(message, color: .red)
            }
            Divider().padding(.vertical, 5).padding(.horizontal, MenuItem.inset)
            MenuItem(title: "Settings…", shortcut: "⌘,", action: openSettings)
                .keyboardShortcut(",")
            MenuItem(title: "Quit Halo", shortcut: "⌘Q") { NSApplication.shared.terminate(nil) }
                .keyboardShortcut("q")
        }
        .padding(5)
        .frame(width: 280)
    }

    private var header: some View {
        HStack {
            Text("Boost Brightness").font(.system(size: 13, weight: .semibold))
            Spacer()
            Toggle("Boost Brightness", isOn: $controller.isEnabled)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
                .disabled(!controller.hasCapableDisplay)
        }
        .padding(.horizontal, MenuItem.inset)
        .padding(.top, 6)
        .padding(.bottom, 12)
    }

    private var strength: some View {
        VStack(alignment: .leading, spacing: 4) {
            Slider(value: $controller.factor, in: BoostFactor.range)
                .controlSize(.small)
            Text("\(Int(((controller.factor - 1) * 100).rounded()))% brighter than normal")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, MenuItem.inset)
        .padding(.bottom, 4)
    }

    private func note(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.system(size: 11))
            .foregroundStyle(color)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, MenuItem.inset)
            .padding(.bottom, 4)
    }
}

/// A menu item row: highlighted under the pointer, with its shortcut on the right.
private struct MenuItem: View {
    static let inset: CGFloat = 9

    let title: String
    let shortcut: String
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack {
                Text(title)
                Spacer()
                Text(shortcut).foregroundStyle(.secondary)
            }
            .font(.system(size: 13))
            .padding(.horizontal, Self.inset)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(isHovered ? Color.primary.opacity(0.1) : .clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}
