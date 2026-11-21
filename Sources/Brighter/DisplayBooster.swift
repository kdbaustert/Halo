import AppKit

/// Boosts one display: keeps it in EDR mode and scales its gamma table, then puts the table it
/// found back when stopped.
@MainActor
final class DisplayBooster {
    let displayID: CGDirectDisplayID
    private let originalTable: GammaTable
    private let edrWindow: EDRWindow

    init(screen: NSScreen, displayID: CGDirectDisplayID) throws {
        self.displayID = displayID
        originalTable = try GammaTable.current(for: displayID)
        edrWindow = try EDRWindow(screen: screen)
    }

    /// Safe to call again with the same factor: it writes the same table, never a table scaled
    /// from an already scaled one.
    func apply(factor: Float) throws {
        edrWindow.show(brightness: factor)
        try originalTable.scaled(by: factor).apply(to: displayID)
    }

    func stop() throws {
        edrWindow.close()
        try originalTable.apply(to: displayID)
    }
}
