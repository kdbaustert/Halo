import AppKit
import SwiftUI

/// Opens the Settings window the way Cmd-Tab does: a glass window, with Halo acting as an
/// ordinary app (Dock tile, menu bar) only while it's open.
@MainActor
final class SettingsPresenter: NSObject, NSWindowDelegate, NSMenuItemValidation {
    private let settings: AppSettings
    private var window: NSWindow?

    init(settings: AppSettings) {
        self.settings = settings
    }

    func show() {
        let window = self.window ?? makeWindow()
        self.window = window
        window.delegate = self
        // Installed before the policy change, so the menu bar is never momentarily empty.
        if NSApp.mainMenu == nil { NSApp.mainMenu = makeMainMenu() }
        NSApp.setActivationPolicy(.regular)
        window.makeKeyAndOrderFront(nil)
        // The polite `activate()` can be declined while the activation policy is changing, and
        // then the window opens behind whatever was in front.
        NSApp.activate(ignoringOtherApps: true)
    }

    /// Back to a menu bar app once the window goes, and the window is let go of so its views
    /// don't keep updating while nobody can see them.
    func windowWillClose(_ notification: Notification) {
        settings.stopRecordingShortcut()
        // Next turn of the run loop: removing the Dock tile while the window is still closing can
        // leave the tile behind.
        DispatchQueue.main.async { [weak self] in
            // Reopened in that same turn, so it keeps the tile and the window.
            guard self?.window?.isVisible != true else { return }
            NSApp.setActivationPolicy(.accessory)
            self?.window = nil
        }
    }

    @objc func closeSettings(_ sender: Any?) {
        window?.performClose(sender)
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        guard menuItem.action == #selector(closeSettings(_:)) else { return true }
        return window != nil
    }

    /// The menu bar that comes with the Dock tile. ⌘Q closes Settings rather than quitting, because
    /// quitting takes the boost down with it; Quit Halo stays in the menu without a key.
    private func makeMainMenu() -> NSMenu {
        let main = NSMenu()

        let appMenu = NSMenu()
        appMenu.addItem(
            withTitle: "Hide Halo", action: #selector(NSApplication.hide(_:)),
            keyEquivalent: "h")
        let hideOthers = appMenu.addItem(
            withTitle: "Hide Others", action: #selector(NSApplication.hideOtherApplications(_:)),
            keyEquivalent: "h")
        hideOthers.keyEquivalentModifierMask = [.command, .option]
        appMenu.addItem(
            withTitle: "Show All", action: #selector(NSApplication.unhideAllApplications(_:)),
            keyEquivalent: "")
        appMenu.addItem(.separator())
        let close = appMenu.addItem(
            withTitle: "Close Settings", action: #selector(closeSettings(_:)), keyEquivalent: "q")
        close.target = self
        appMenu.addItem(
            withTitle: "Quit Halo", action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "")
        let appItem = NSMenuItem()
        appItem.submenu = appMenu
        main.addItem(appItem)

        let windowMenu = NSMenu(title: "Window")
        windowMenu.addItem(
            withTitle: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)),
            keyEquivalent: "m")
        windowMenu.addItem(
            withTitle: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        let windowItem = NSMenuItem()
        windowItem.submenu = windowMenu
        main.addItem(windowItem)

        return main
    }

    private func makeWindow() -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 640, height: 400),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false)
        window.title = "Halo Settings"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        // The glass needs a clear window under it, or the material has nothing to blur and
        // renders flat grey.
        window.isOpaque = false
        window.backgroundColor = .clear
        window.titlebarSeparatorStyle = .none
        // The presenter's reference frees it, after the close.
        window.isReleasedWhenClosed = false
        window.contentView = glassContent()
        window.center()
        window.setFrameAutosaveName("BrighterSettings")
        return window
    }

    /// The glass goes on an AppKit view under the SwiftUI content so it also covers the titlebar
    /// strip behind the traffic lights.
    private func glassContent() -> NSView {
        let backdrop = NSVisualEffectView()
        backdrop.material = .underWindowBackground
        backdrop.blendingMode = .behindWindow
        backdrop.state = .active

        let host = NSHostingView(rootView: SettingsRootView(settings: settings))
        host.translatesAutoresizingMaskIntoConstraints = false
        backdrop.addSubview(host)
        NSLayoutConstraint.activate([
            host.topAnchor.constraint(equalTo: backdrop.topAnchor),
            host.leadingAnchor.constraint(equalTo: backdrop.leadingAnchor),
            host.trailingAnchor.constraint(equalTo: backdrop.trailingAnchor),
            host.bottomAnchor.constraint(equalTo: backdrop.bottomAnchor),
        ])
        return backdrop
    }
}
