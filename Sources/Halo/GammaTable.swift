import CoreGraphics

/// A display's transfer table, one curve per channel, as CoreGraphics reads and writes it.
struct GammaTable: Equatable {
    var red: [CGGammaValue]
    var green: [CGGammaValue]
    var blue: [CGGammaValue]

    static func current(for display: CGDirectDisplayID) throws -> GammaTable {
        let capacity = CGDisplayGammaTableCapacity(display)
        var red = [CGGammaValue](repeating: 0, count: Int(capacity))
        var green = red
        var blue = red
        var sampleCount: UInt32 = 0
        let error = CGGetDisplayTransferByTable(
            display, capacity, &red, &green, &blue, &sampleCount)
        guard error == .success else {
            throw BoostError.gammaRead(display: display, error: error)
        }
        let count = Int(sampleCount)
        return GammaTable(
            red: Array(red.prefix(count)),
            green: Array(green.prefix(count)),
            blue: Array(blue.prefix(count)))
    }

    /// Multiplies every output value. Results above 1.0 are the point: with the display in EDR
    /// mode they reach the panel as light past SDR white instead of being clipped.
    func scaled(by factor: Float) -> GammaTable {
        GammaTable(
            red: red.map { $0 * factor },
            green: green.map { $0 * factor },
            blue: blue.map { $0 * factor })
    }

    func apply(to display: CGDirectDisplayID) throws {
        let error = CGSetDisplayTransferByTable(
            display, UInt32(red.count), red, green, blue)
        guard error == .success else {
            throw BoostError.gammaWrite(display: display, error: error)
        }
    }
}
