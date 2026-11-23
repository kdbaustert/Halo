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

    /// Safe to call again with the same values: it writes the same table, never a table scaled
    /// from an already scaled one. `fade` runs from 0 (the table as found) to 1 (the full
    /// factor). Only the table fades: the pixel stays at the full factor, so the panel is already
    /// in EDR mode when the table needs it and the window isn't redrawn every frame.
    func apply(factor: Float, fade: Float) throws {
        edrWindow.show(brightness: factor)
        try originalTable.scaled(by: BoostFactor.faded(factor, by: fade)).apply(to: displayID)
    }

    func stop() throws {
        edrWindow.close()
        try originalTable.apply(to: displayID)
    }
}
